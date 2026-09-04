# Airflow + Kubernetes VICAR Pipeline Example

Apache Airflow + Kubernetes pipeline for event-driven VICAR terrain mesh generation. Demonstrates orchestrating stereo image processing (radiometric correction → correlation → XYZ → mesh) using ephemeral Kubernetes pods with fast worker spin-up. Everything runs inside minikube from open-source images — no cloud account or AWS emulator needed.

## Architecture

**Components:**
- **RabbitMQ:** AMQP broker; exchange `ids-events` → queue `ids-fdr-queue` (pre-declared from a definitions file)
- **MinIO:** S3-compatible object store; bucket notifications publish ObjectCreated events to RabbitMQ
- **Seed Job (`mc`):** Creates the bucket, subscribes it to the RabbitMQ target, uploads stereo image pairs
- **Listener (Python/pika):** Consumes the queue, buffers stereo pairs, triggers Airflow DAGs
- **Airflow (Helm):** KubernetesExecutor, orchestrates VICAR tasks as ephemeral pods
- **VICAR pods (tig-worker):** Download from MinIO → run VICAR → upload to MinIO → exit
- **Storage:** S3-API round-trip per task (stateless pods)

**Data Flow:**
1. Seed uploads stereo FDR pairs to MinIO
2. MinIO ObjectCreated (`.VIC` suffix filter) → AMQP publish → RabbitMQ `ids-events` → `ids-fdr-queue`
3. Listener consumes the queue, buffers stereo pairs by frame id, triggers DAG once both L+R arrive
4. Airflow launches the 8-task `ids_terrain_ncam` DAG: `rad_left/right` → `correlate_left/right` → `xyz_left/right` → `mesh_left/right`
5. Each task = ephemeral tig-worker pod (download → VICAR → upload)
6. Final outputs: `.obj/.mtl/.png` under the ODS prefix `s3://ids-pipeline/output/sol/<NNNNN>/ids/rdr/ncam/` (sol 1835 → `output/sol/01835/ids/rdr/ncam/`)

## Prerequisites

- **minikube** (v1.30+, Kubernetes 1.27+)
- **kubectl**
- **Helm 3**
- **Docker or Podman** (for building listener + worker images)
- **TIG base image:** `ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource`
- **Calibration data:** VISOR M20 calibration (see [Calibration Setup](#5-calibration-setup))
- **Sample data:** Stereo FDR image pairs (see [Sample Data](#6-sample-data))

## Setup

### 1. Start minikube

```bash
minikube start --cpus=4 --memory=8192 --driver=docker
eval $(minikube docker-env)
```

### 2. Create namespace

```bash
kubectl create namespace tig-airflow
```

### 3. Build listener image

(`docker` below can be replaced with `podman`; if the image is built outside minikube's daemon, load it with `minikube image load <tag>` as in step 4.)

```bash
cd k8s/listener
docker build -t ids-listener:latest .
```

### 4. Build the VICAR worker image

The base TIG image has VICAR binaries but **no AWS CLI**. Build worker image layering AWS CLI v2:

```bash
# Pull base TIG image
docker pull ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource

# Build worker (adds AWS CLI)
docker build -t tig-worker:latest -f k8s/worker/Dockerfile .

# Load into minikube
minikube image load tig-worker:latest
```

### 5. Calibration Setup

VISOR calibration is published as assets of the [VICAR 5.0 release](https://github.com/NASA-AMMOS/VICAR/releases/tag/5.0), not as a git repository. M20 calibration is 2.69 GB compressed / 5.3 GB extracted, split across two parts because GitHub caps a release asset at 2 GB:

```bash
mkdir -p visor_data
curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/5.0/visor_calibration_20230608_m20.tar.gzaa" \
        "https://github.com/NASA-AMMOS/VICAR/releases/download/5.0/visor_calibration_20230608_m20.tar.gzab" | \
  tar -zxf - -C visor_data
```

The mission directory `visor_data/calibration/m20` (the one directly containing `camera_models/`) is what gets mounted at `/mnt/calib` in [step 7](#7-start-required-minikube-mounts). See [Downloading VISOR Data](../../docs/demos/downloading-visor-data.md) for the other missions and for sample data.

### 6. Sample Data

#### Option A: Use your own stereo FDR pairs

Place stereo image pairs in a directory structure:
```
sample-data/
  NLM_<sol>_<frame>_<product>FDR_<id>.VIC  # Left eye
  NRM_<sol>_<frame>_<product>FDR_<id>.VIC  # Right eye
```

#### Option B: Download M2020 archive data

The pair used by the seed job (sol 1835) is in the PDS Imaging Node archive, release r16 of the `mars2020_navcam_ops_calibrated` bundle. The `.IMG` files carry a VICAR label, so they are saved as `.VIC`:

```bash
mkdir -p sample-data
B=https://pds-imaging.jpl.nasa.gov/archive/m20/r16/mars2020_navcam_ops_calibrated/data/sol/01835/ids/fdr/ncam
for f in NLM_1835_0829848458_777FDR_N0874924NCAM00230_0A02LLJ01 NRM_1835_0829848458_777FDR_N0874924NCAM00230_0A02LLJ01; do
  curl -L -o sample-data/$f.VIC "$B/$f.IMG"
done
head -c 40 sample-data/NLM_*.VIC   # must start with ODL_VERSION_ID / LBLSIZE, not <html>
```

To find other pairs, query the [PDS Search API](https://pds.nasa.gov/api/search/1/products?q=(lid%20like%20%22urn:nasa:pds:mars2020_navcam_ops_calibrated:data:nlm_1835*fdr*%22)&fields=ops:Data_File_Info.ops:file_ref) by LID (`urn:nasa:pds:mars2020_navcam_ops_calibrated:data:n[lr]m_<sol>_<sclk>_<ms>fdr_...`) — the `ops:Data_File_Info.ops:file_ref` field is the download URL. The `planetarydata.jpl.nasa.gov` browse tree only exposes early releases and returns an HTML landing page for missing paths.

### 7. Start required minikube mounts

Three host directories must stay mounted — run each in its own terminal, or background them, and keep them running for the whole session:

```bash
# DAGs → Airflow scheduler/webserver/workers
minikube mount $(pwd)/dags:/mnt/dags &

# VICAR calibration (step 5) → every VICAR pod at /usr/local/vicar/mars_calib
minikube mount /path/to/visor_data/calibration/m20:/mnt/calib &

# Sample data (step 6) → seed job
minikube mount /path/to/sample-data:/mnt/sample-data &
```

If `minikube mount` fails with `HOST_UNSUPPORTED` (no 9p support on the host), copy the
directories into the node instead, e.g. `docker cp /path/to/sample-data minikube:/mnt/sample-data`
(or `minikube cp` per file).

### 8. Deploy RabbitMQ and MinIO

MinIO validates its AMQP notification target at startup, so RabbitMQ goes first (the MinIO pod has an init container that waits for it):

```bash
kubectl apply -f k8s/rabbitmq/deployment.yaml
kubectl wait --for=condition=ready pod -l app=rabbitmq -n tig-airflow --timeout=180s

kubectl apply -f k8s/minio/deployment.yaml
kubectl wait --for=condition=ready pod -l app=minio -n tig-airflow --timeout=180s
```

The RabbitMQ definitions ConfigMap pre-declares the `ids-events` fanout exchange, the durable `ids-fdr-queue`, and their binding, so events published before the listener starts are retained.

### 9. Deploy Airflow

Airflow logs persist via hostPath PV/PVC (survives worker pod deletion):

```bash
# Mount host dir for Airflow logs (uid 50000 = airflow user)
minikube mount $(pwd)/airflow-logs:/mnt/airflow-logs --uid 50000 --gid 0 &

# Create ReadWriteMany hostPath PV + PVC
kubectl apply -f k8s/airflow/logs-pv.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/tig-airflow-logs-host -n tig-airflow --timeout=60s

# Create static webserver secret (prevents restart/logout churn)
kubectl create secret generic ids-webserver-secret-key --namespace tig-airflow \
  --from-literal=webserver-secret-key="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"

# Add Helm repo
helm repo add apache-airflow https://airflow.apache.org
helm repo update

# Install Airflow (chart 1.11.0 = Airflow 2.7.1). Do not pass --wait: the DB
# migrations Job is a post-install hook, so --wait deadlocks until it times out.
# helm install itself blocks until the migrations hook has completed.
helm install airflow apache-airflow/airflow --version 1.11.0 \
  -f k8s/airflow/values.yaml --namespace tig-airflow

# Wait for webserver
kubectl wait --for=condition=ready pod -l component=webserver -n tig-airflow --timeout=600s
```

### 10. Deploy wrapper scripts ConfigMap

```bash
kubectl apply -f k8s/airflow/vicar-wrappers-configmap.yaml
```

### 11. Run seed job

Update `k8s/seed/job.yaml` to reference your sample data mount path, then:

```bash
kubectl apply -f k8s/seed/job.yaml
kubectl wait --for=condition=complete job/ids-seed -n tig-airflow --timeout=300s
kubectl logs job/ids-seed -n tig-airflow
```

**Expected output:**
- Bucket `ids-pipeline` created
- Bucket event `arn:minio:sqs::RABBITMQ:amqp` added for `s3:ObjectCreated:*` with suffix `.VIC`
- Files uploaded to `s3://ids-pipeline/global_cache/<sol>/<instrument>/`

MinIO publishes one event per upload to the `ids-events` exchange; they sit in `ids-fdr-queue` until the listener consumes them. Inspect the queue at any time via the management UI:

```bash
kubectl port-forward svc/rabbitmq 15672:15672 -n tig-airflow
# Open http://localhost:15672 (guest/guest) → Queues → ids-fdr-queue
```

### 12. Deploy listener

```bash
kubectl apply -f k8s/listener/deployment.yaml
kubectl wait --for=condition=ready pod -l app=ids-listener -n tig-airflow --timeout=120s
kubectl logs -f deployment/ids-listener -n tig-airflow
```

**Expected output:**
```
=== IDS Pipeline Listener ===
...
Consuming from queue ids-fdr-queue (exchange ids-events)
Received: s3://ids-pipeline/global_cache/.../NLM_...FDR_...VIC
  Matched process: ids_terrain_ncam
  Frame: ..., Eye: left
  Waiting for right eye (timeout in 300s)
Received: s3://ids-pipeline/global_cache/.../NRM_...FDR_...VIC
  Stereo pair complete
✓ Triggered DAG ids_terrain_ncam
```

### 13. Monitor DAG execution

```bash
# Port-forward Airflow UI
kubectl port-forward svc/airflow-webserver 8080:8080 -n tig-airflow

# Open http://localhost:8080 (admin/admin)
```

**OR via CLI:**
```bash
kubectl logs -l dag_id=ids_terrain_ncam --tail=100 --prefix --all-containers
```

### 14. Verify outputs

```bash
# Port-forward MinIO (9000 = S3 API, 9001 = web console)
kubectl port-forward svc/minio 9000:9000 9001:9001 -n tig-airflow

# List outputs (ODS layout: output/sol/<NNNNN>/ids/rdr/ncam/)
export AWS_ACCESS_KEY_ID=minioadmin AWS_SECRET_ACCESS_KEY=minioadmin AWS_DEFAULT_REGION=us-west-2
aws --endpoint-url=http://localhost:9000 s3 ls s3://ids-pipeline/output/ --recursive

# Download (seeded sol 1835)
aws --endpoint-url=http://localhost:9000 s3 cp \
  s3://ids-pipeline/output/sol/01835/ids/rdr/ncam/ ./outputs/ --recursive
```

Or browse the bucket at http://localhost:9001 (minioadmin/minioadmin).

### 15. Re-trigger by dropping a file

The pipeline is purely event-driven: uploading a new stereo pair anywhere under `global_cache/<sol>/ncam/` fires the DAG again with no seed job involved.

```bash
aws --endpoint-url=http://localhost:9000 s3 cp NLM_<...>FDR_<...>.VIC s3://ids-pipeline/global_cache/<sol>/ncam/
aws --endpoint-url=http://localhost:9000 s3 cp NRM_<...>FDR_<...>.VIC s3://ids-pipeline/global_cache/<sol>/ncam/
```

## Project Structure

```
.
├── README.md
├── dags/
│   └── ids_terrain_ncam.py      # DAG: rad → correlate → xyz → mesh
├── k8s/
│   ├── rabbitmq/
│   │   └── deployment.yaml      # AMQP broker + pre-declared exchange/queue
│   ├── minio/
│   │   └── deployment.yaml      # S3-compatible store, notifications -> RabbitMQ
│   ├── seed/
│   │   └── job.yaml             # Setup job (embeds seed.sh in a ConfigMap)
│   ├── listener/
│   │   ├── Dockerfile
│   │   ├── listener.py          # RabbitMQ consumer + Airflow trigger
│   │   └── deployment.yaml
│   ├── worker/
│   │   └── Dockerfile           # tig-worker (TIG base + AWS CLI)
│   └── airflow/
│       ├── values.yaml
│       ├── logs-pv.yaml
│       └── vicar-wrappers-configmap.yaml
└── wrappers/
    ├── rad_wrapper.sh           # marsrad
    ├── correlate_wrapper.sh     # marsecorr + marscor3
    ├── xyz_wrapper.sh           # marsxyz + filters
    └── mesh_wrapper.sh          # marsmesh + vicario
```

## VICAR Pipeline (per DAG run)

Eight tasks, two per stage:

1. **rad_left, rad_right** (parallel): `marsrad` FDR→RAS radiometric correction
2. **correlate_left, correlate_right** (parallel): `marsecorr` + `marscor3` → disparity maps
3. **xyz_left, xyz_right** (parallel): `marsxyz` → pointcloud, `marsrfilt` + `m20filter` + `marsfilter` + `marsmask` → filters
4. **mesh_left, mesh_right** (parallel): `marsmesh` → `.obj` mesh, `vicario` → `.png` texture

**Total runtime:** ~6-7 minutes (minikube, 4 CPU)  
**Pod spin-up:** ~1-3s (image pre-pulled)

## Troubleshooting

**Pods stuck Pending:**
- Check: `kubectl describe pod <pod-name>`
- Verify image loaded: `minikube image ls | grep tig-worker`

**Wrapper script fails:**
- Check: `kubectl logs <pod-name>`
- Common issues: S3 endpoint unreachable, input not found, calibration mount missing

**MinIO pod stuck in Init:**
- Its init container waits for `rabbitmq:5672`; check `kubectl get pod -l app=rabbitmq -n tig-airflow`

**Events not reaching the listener:**
- Confirm the bucket subscription: `kubectl logs job/ids-seed -n tig-airflow` should show `arn:minio:sqs::RABBITMQ:amqp`
- Check the queue depth in the RabbitMQ management UI (step 11); if messages pile up, the listener is not consuming — check `kubectl logs deployment/ids-listener -n tig-airflow`
- Only `.VIC` uploads generate events (suffix filter in `seed.sh`)

**DAG not visible:**
- Check DAG mount: `kubectl exec -it deployment/airflow-scheduler -- ls /opt/airflow/dags`
- Verify minikube mount running: `minikube mount $(pwd)/dags:/mnt/dags`

## Implementation Notes

- **Object store:** MinIO speaks the S3 API, so workers keep using the AWS CLI with `--endpoint-url` and the MinIO root credentials (`minioadmin`/`minioadmin`, demo only). `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` is kept so newer AWS CLI releases do not send trailing checksums the store may reject
- **Event bridge:** MinIO's built-in AMQP notification target (`MINIO_NOTIFY_AMQP_*_RABBITMQ` env vars on the MinIO pod) publishes S3-format `Records[]` JSON straight to the `ids-events` exchange; there is no SNS/SQS layer. Object keys arrive URL-encoded and the listener decodes them
- **Queue semantics:** the listener uses manual acks with `prefetch_count=10`. An event is acked once its record is buffered or its DAG trigger succeeds; if Airflow rejects the trigger the event is nacked and requeued after `RETRY_DELAY` (the completed pair stays buffered and is not expired, so the redelivery re-triggers it). Unparseable bodies are rejected without requeue so a poison message cannot loop
- **Credentials:** `minioadmin`/`minioadmin`, `guest`/`guest` and Airflow `admin`/`admin` are hardcoded demo values on a single-node minikube; for anything shared, move them into Kubernetes Secrets, create a scoped MinIO user/policy for the workers, and a non-admin RabbitMQ user for the listener
- **VICAR exit codes:** Several tools exit non-zero on success. Wrappers use file-existence checks (`... || true` then verify output)
- **Calibration:** Wrappers set `MARS_CONFIG_PATH=/usr/local/vicar/mars_calib`; DAG mounts calib hostPath read-only
- **Helm chart pin:** Chart 1.11.0 (Airflow 2.7.1). Newer charts ship Airflow 3.x, breaking listener `/api/v1` usage
- **Log persistence:** `logs.persistence` + `existingClaim: airflow-logs-host` preserves logs after pod deletion
- **Webserver secret:** Static key prevents restart churn (the chart otherwise generates a random one per upgrade, invalidating sessions). Create it with the `kubectl create secret` command in step 9 — there is no manifest for it, so no key is ever committed. The data key must be exactly `webserver-secret-key`, and the secret must NOT be named `airflow-webserver-secret-key` (Helm owns that name and prunes it mid-upgrade)

## References

- **TIG repository:** https://github.com/NASA-AMMOS/tig
- **VISOR calibration:** [Downloading VISOR Data](../../docs/demos/downloading-visor-data.md) · [VICAR 5.0 release assets](https://github.com/NASA-AMMOS/VICAR/releases/tag/5.0)
- **M2020 archive:** https://pds-geosciences.wustl.edu/missions/mars2020/ · https://mars.nasa.gov/mmgis-maps/M20/Layers/json/
