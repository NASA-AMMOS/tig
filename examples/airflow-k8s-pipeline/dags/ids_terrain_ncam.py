"""
M20 IDS Terrain Processing DAG — per-eye, RAS-named products.

Converts BPMN chain: rad -> correlate -> xyz -> mesh, run genuinely per-eye
(left = NLM, right = NRM) to reproduce production IDS behavior.

Graph (8 tasks):
    rad_left  ─┐
               ├─> correlate_left  (l2r) ─> xyz_left  ─> mesh_left   (NLM_...M777RAS)
    rad_right ─┤
               └─> correlate_right (r2l) ─> xyz_right ─> mesh_right  (NRM_...M777RAS)

Naming: FDR key -> RAS basename via `_777FDR_` -> `M777RAS`.
Downstream products reuse the RAS basename, swapping only the product-type
field [23:26] (RAS -> XYZ/XYM/...) + extension. Mesh outputs keep the RAS token.
Nominal ODS output path: output/<sol_path>/ids/rdr/ncam/ where
sol_path = "sol/{:05d}".format(int(basename[4:8])).
"""
from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import KubernetesPodOperator
from kubernetes.client import models as k8s

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
S3_ENDPOINT = "http://minio.tig-airflow.svc.cluster.local:9000"
BUCKET = "ids-pipeline"
VICAR_IMAGE = "tig-worker:latest"  # TIG :opensource base + AWS CLI v2 (k8s/worker/Dockerfile)

default_args = {
    "owner": "ids-pipeline",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 0,  # fail fast, match BPMN retries=0
    "retry_delay": timedelta(minutes=1),
}


# ---------------------------------------------------------------------------
# Product name derivation
# ---------------------------------------------------------------------------
def _basename(key: str) -> str:
    """S3 key -> filename without directory or extension."""
    fn = key.rsplit("/", 1)[-1]
    return fn.rsplit(".", 1)[0]


def fdr_to_ras_base(fdr_key: str) -> str:
    """FDR S3 key -> RAS product basename (no dir, no extension).

    Column-precise M20 filename transform on the 54-char basename:
        char[19]    '_'   -> 'M'   (compression/venue field)
        chars[23:26] 'FDR' -> 'RAS' (product-type field)
    e.g. NLM_1835_0829848458_777FDR_N0874924NCAM00230_0A02LLJ01
      -> NLM_1835_0829848458M777RAS_N0874924NCAM00230_0A02LLJ01
    Net effect == substring swap '_777FDR' -> 'M777RAS' (both 7 chars).
    """
    b = _basename(fdr_key)
    if b[19] != "_" or b[23:26] != "FDR":
        raise ValueError(f"unexpected FDR basename layout: {b!r}")
    return b[:19] + "M" + b[20:23] + "RAS" + b[26:]


def product_name(ras_base: str, product_type: str, ext: str) -> str:
    """Swap product-type field [23:26] of a RAS basename, set extension.

    product_type is a 3-char code (RAS, XYZ, XYM, DSP, ...). ext without dot.
    """
    if len(product_type) != 3:
        raise ValueError(f"product_type must be 3 chars: {product_type!r}")
    swapped = ras_base[:23] + product_type + ras_base[26:]
    return f"{swapped}.{ext}"


def sol_path(ras_base: str) -> str:
    """RAS basename -> 'sol/NNNNN' nominal ODS sol path (zero-padded to 5)."""
    return "sol/{:05d}".format(int(ras_base[4:8]))


def ods_prefix(ras_base: str) -> str:
    """RAS basename -> 'output/<sol_path>/ids/rdr/ncam' ODS output prefix."""
    return f"output/{sol_path(ras_base)}/ids/rdr/ncam"


# ---------------------------------------------------------------------------
# Pod plumbing (volumes / mounts / env) — shared by all tasks
# ---------------------------------------------------------------------------
wrapper_volume = k8s.V1Volume(
    name="wrappers",
    config_map=k8s.V1ConfigMapVolumeSource(name="vicar-wrappers", default_mode=0o755),
)
wrapper_mount = k8s.V1VolumeMount(name="wrappers", mount_path="/opt/wrappers", read_only=True)

calib_volume = k8s.V1Volume(
    name="mars-calib",
    host_path=k8s.V1HostPathVolumeSource(path="/mnt/calib", type="Directory"),
)
calib_mount = k8s.V1VolumeMount(
    name="mars-calib", mount_path="/usr/local/vicar/mars_calib", read_only=True
)

pod_volumes = [wrapper_volume, calib_volume]
pod_volume_mounts = [wrapper_mount, calib_mount]

env_vars = [
    k8s.V1EnvVar(name="AWS_ACCESS_KEY_ID", value="minioadmin"),
    k8s.V1EnvVar(name="AWS_SECRET_ACCESS_KEY", value="minioadmin"),
    k8s.V1EnvVar(name="AWS_DEFAULT_REGION", value="us-west-2"),
    k8s.V1EnvVar(name="AWS_REQUEST_CHECKSUM_CALCULATION", value="when_required"),
]


def vicar_task(
    task_id: str,
    name: str,
    wrapper: str,
    arguments: list,
    cpu: str = "1",
    memory: str = "2Gi",
) -> KubernetesPodOperator:
    """Factory for a VICAR worker pod task.

    Per-task pod sizing (maps from CWS per-class autoscaling -> per-pod
    requests/limits): `cpu`/`memory` set the pod's resource requests AND limits.
    Requests drive scheduling (on a 4-CPU minikube node, tasks whose requests
    exceed available CPU wait Pending, serializing instead of overcommitting).
    Limits cap usage — keep cpu limit >= the OMP thread count for correlate.
    Real K8s: add node_selector/affinity to land heavy pods on large nodes.
    """
    return KubernetesPodOperator(
        task_id=task_id,
        name=name,
        namespace="tig-airflow",
        image=VICAR_IMAGE,
        cmds=["/bin/bash"],
        arguments=[f"/opt/wrappers/{wrapper}", S3_ENDPOINT, BUCKET] + arguments,
        env_vars=env_vars,
        volumes=pod_volumes,
        volume_mounts=pod_volume_mounts,
        container_resources=k8s.V1ResourceRequirements(
            requests={"cpu": cpu, "memory": memory},
            limits={"cpu": cpu, "memory": memory},
        ),
        image_pull_policy="IfNotPresent",
        get_logs=True,
        is_delete_operator_pod=True,
    )


# ---------------------------------------------------------------------------
# DAG — 8-task per-eye graph
# ---------------------------------------------------------------------------
# S3 key templates. All name derivation happens in Jinja via the helpers above,
# which are registered as user_defined_macros so runtime conf (left_key/right_key)
# drives naming. Conf shape: {bucket, left_key, right_key, run_id}.
#
#   RAS   (per eye) : processque/<run_id>/<RAS_BASE>.VIC
#   DSP   (per eye) : processque/<run_id>/<DSP_BASE>.img
#   XYM   (per eye) : processque/<run_id>/<XYM_BASE>.xym
#   MESH  (per eye) : <ods_prefix>/<RAS_BASE>.{obj,mtl,png,lbl,iv}
#
# Jinja shorthands used below:
#   LK / RK  = dag_run.conf left_key / right_key (FDR input keys)
#   LB / RB  = fdr_to_ras_base(LK) / (RK)   -- RAS basenames
LK = "{{ dag_run.conf['left_key'] }}"
RK = "{{ dag_run.conf['right_key'] }}"
LB = "{{ fdr_to_ras_base(dag_run.conf['left_key']) }}"
RB = "{{ fdr_to_ras_base(dag_run.conf['right_key']) }}"
PQ = "processque/{{ run_id }}"

# per-eye processque keys
RAS_L = f"{PQ}/{LB}.VIC"
RAS_R = f"{PQ}/{RB}.VIC"
DSP_L = "%s/{{ product_name(fdr_to_ras_base(dag_run.conf['left_key']),  'DSP', 'img') }}" % PQ
DSP_R = "%s/{{ product_name(fdr_to_ras_base(dag_run.conf['right_key']), 'DSP', 'img') }}" % PQ
XYM_L = "%s/{{ product_name(fdr_to_ras_base(dag_run.conf['left_key']),  'XYM', 'xym') }}" % PQ
XYM_R = "%s/{{ product_name(fdr_to_ras_base(dag_run.conf['right_key']), 'XYM', 'xym') }}" % PQ
# mesh output prefixes (ODS)
ODS_L = "{{ ods_prefix(fdr_to_ras_base(dag_run.conf['left_key'])) }}"
ODS_R = "{{ ods_prefix(fdr_to_ras_base(dag_run.conf['right_key'])) }}"

with DAG(
    dag_id="ids_terrain_ncam",
    default_args=default_args,
    description="M20 NCAM per-eye terrain mesh generation (FDR -> RAS -> mesh)",
    schedule_interval=None,  # triggered by listener
    start_date=datetime(2026, 7, 20),
    catchup=False,
    max_active_runs=1,  # correlate_* need 2 CPU each; overlapping runs starve on a 4-CPU minikube
    is_paused_upon_creation=False,
    user_defined_macros={
        "fdr_to_ras_base": fdr_to_ras_base,
        "product_name": product_name,
        "sol_path": sol_path,
        "ods_prefix": ods_prefix,
    },
    tags=["m2020", "ids", "terrain", "vicar", "per-eye"],
) as dag:

    # Per-task pod sizing (minikube has 4 CPU total; requests drive scheduling).
    #   rad       : light  (FDR->RAS radiometric, fast)
    #   correlate : heavy  (marsecorr+marscor3 stereo, CPU-bound, -omp_on)
    #   xyz       : medium (marsxyz+filters, moderate)
    #   mesh      : memory-heavy (marsmesh builds large obj/vertex buffers)
    # correlate_left/right each request 2 CPU: on a 4-CPU node they can still
    # run in parallel, but co-scheduled heavy pods (e.g. correlate + mesh) will
    # serialize via Pending rather than overcommit.

    # rad: FDR -> RAS per eye.  args: <input_fdr_key> <output_ras_key> <run_id>
    rad_left = vicar_task(
        "rad_left", "rad-left", "rad_wrapper.sh",
        [LK, RAS_L, "{{ run_id }}"],
        cpu="1", memory="1Gi",
    )
    rad_right = vicar_task(
        "rad_right", "rad-right", "rad_wrapper.sh",
        [RK, RAS_R, "{{ run_id }}"],
        cpu="1", memory="1Gi",
    )

    # correlate: per direction.  args: <left_ras_key> <right_ras_key> <disparity_out_key> <run_id> <eye>
    # left direction (l2r): pair order (left, right) -> DSP_L
    correlate_left = vicar_task(
        "correlate_left", "correlate-left", "correlate_wrapper.sh",
        [RAS_L, RAS_R, DSP_L, "{{ run_id }}", "left"],
        cpu="2", memory="4Gi",
    )
    # right direction (r2l): pair order swapped (right, left) -> DSP_R
    correlate_right = vicar_task(
        "correlate_right", "correlate-right", "correlate_wrapper.sh",
        [RAS_R, RAS_L, DSP_R, "{{ run_id }}", "right"],
        cpu="2", memory="4Gi",
    )

    # xyz: per eye.  args: <left_ras_key> <right_ras_key> <disparity_key> <xym_out_key> <run_id> <eye>
    xyz_left = vicar_task(
        "xyz_left", "xyz-left", "xyz_wrapper.sh",
        [RAS_L, RAS_R, DSP_L, XYM_L, "{{ run_id }}", "left"],
        cpu="1", memory="3Gi",
    )
    xyz_right = vicar_task(
        "xyz_right", "xyz-right", "xyz_wrapper.sh",
        [RAS_R, RAS_L, DSP_R, XYM_R, "{{ run_id }}", "right"],
        cpu="1", memory="3Gi",
    )

    # mesh: per eye.  args: <xym_key> <ras_key> <ods_prefix> <ras_base> <run_id> <eye>
    mesh_left = vicar_task(
        "mesh_left", "mesh-left", "mesh_wrapper.sh",
        [XYM_L, RAS_L, ODS_L, LB, "{{ run_id }}", "left"],
        cpu="2", memory="6Gi",
    )
    mesh_right = vicar_task(
        "mesh_right", "mesh-right", "mesh_wrapper.sh",
        [XYM_R, RAS_R, ODS_R, RB, "{{ run_id }}", "right"],
        cpu="2", memory="6Gi",
    )

    # Dependencies: both RAS feed each correlate direction.
    [rad_left, rad_right] >> correlate_left
    [rad_left, rad_right] >> correlate_right
    correlate_left >> xyz_left >> mesh_left
    correlate_right >> xyz_right >> mesh_right
