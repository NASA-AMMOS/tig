---
name: testing-airflow-k8s-pipeline
description: How to stand up and end-to-end test examples/airflow-k8s-pipeline (MinIO + RabbitMQ + Airflow KubernetesExecutor) on minikube on a Linux box — tool installs, the minikube mount fallback, the helm --wait deadlock, where evidence lives, and the sample-data trap that makes the DAG fail at correlate_*.
---

# Testing the Airflow + k8s VICAR pipeline on minikube

## Tooling (none preinstalled on the standard box)
```bash
curl -sLO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && sudo install minikube-linux-amd64 /usr/local/bin/minikube
curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install kubectl /usr/local/bin/kubectl
curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
minikube start --cpus=4 --memory=8192 --driver=docker
```
8 CPU / 31 GB boxes are enough. `aws` CLI is preinstalled.

## Building images into minikube
`eval $(minikube docker-env)` selects a containerd-backed daemon whose default buildx driver
does not export images ("Build result will only remain in the build cache", then
`404 page not found`). Use `DOCKER_BUILDKIT=0 docker build ...` (legacy builder) — both
`ids-listener:latest` and `tig-worker:latest` then land in the node directly, no `minikube image load`.

## `minikube mount` may be impossible
`minikube mount` exits with `HOST_UNSUPPORTED: The host does not support filesystem 9p` on
these boxes. Fallback that keeps the manifests' hostPaths unchanged:
```bash
docker cp dags minikube:/mnt/dags
docker cp /path/sample-data minikube:/mnt/sample-data
docker cp /path/visor_data/calibration/m20 minikube:/mnt/calib          # 5.3 GB, run in background
docker exec minikube sh -c 'mkdir -p /mnt/airflow-logs && chown 50000:0 /mnt/airflow-logs'
```
Airflow task logs are then readable with `docker exec minikube find /mnt/airflow-logs -name '*.log'`.

## Helm pitfalls
- Create `ids-webserver-secret-key` BEFORE `helm install`; if forgotten, pods sit in
  `Init:CreateContainerConfigError` — creating the secret afterwards recovers them.
- `helm install --wait` can deadlock: the migrations Job is a post-install hook, and pods loop in
  `wait-for-airflow-migrations` until the timeout. If you see that, `pkill -f "helm install"` then
  `helm upgrade airflow ... ` (without --wait) runs the hook and everything comes up in ~1 min.
- Chain setup commands carefully: one failing `kubectl wait` silently skips everything after `&&`.

## Sample data trap (the thing most likely to waste hours)
The README's sol-1835 M20 NavCam FDR pair is only on the PDS Imaging Node release r16 path
(see the README's download command; commit be020b1). Most other PDS hosts
(planetarydata.jpl.nasa.gov directory URL, pdsimage2.wr.usgs.gov, w10n listings) return
a 24702-byte HTML landing page with HTTP 200 for the `.VIC`/`.IMG` URL. Always
`head -c 100 *.VIC` — `<!DOCTYPE HTML` means fake data. With fake inputs the stack still exercises
the whole event path (seed -> RabbitMQ -> listener -> DAG trigger; rad_* even "succeed" because
the wrapper falls back to copying FDR), but `correlate_*` fails with
`MARSECORR: Could not find a good input file to read`. Get the pair from the user (put it in the
sample-data dir) before claiming the 8-task run works. The VISOR sample tarball has no M20 frames.
Genuine files are 2503680 bytes and start with `ODL_VERSION_ID`. With real data one run takes
~8.5 min on 4 vCPU (correlate_* ~7 min each, marscor3 logs "gore pass N ... % total coverage").

## Capacity: never let two DAG runs overlap on a 4-CPU minikube
correlate_* pods request/limit 2 CPU each (Guaranteed QoS) and the DAG has `retries: 0`. A second
concurrent run's correlate pod sits Unschedulable ("0/1 nodes are available: 1 Insufficient cpu"),
KubernetesPodOperator's 120 s startup timeout fires and the task fails. Re-uploading the pair (step 15)
or re-applying the seed job while a run is in flight WILL fire another run; wait for `Total running = 0`
first, or use `minikube start --cpus=8`. Poll task states cheaply with
`kubectl exec -n tig-airflow airflow-postgresql-0 -- sh -c 'PGPASSWORD=postgres psql -U postgres -d postgres -tA -c "select run_id,task_id,state from task_instance order by 1,2"'`.

## Seed job re-apply
Re-applying `k8s/seed/job.yaml` (`kubectl delete job ids-seed -n tig-airflow; kubectl apply -f k8s/seed/job.yaml`) is the documented way to
re-upload. Before d538e00 the `mc event remove ARN --force` line did not match the suffix-filtered rule
("no notification configuration matched", swallowed by 2>/dev/null) so `mc event add` failed with
"overlapping suffixes" and the pod crashlooped. If you see that, the rule must be removed with the same
`--event put --suffix .VIC` flags (or bucket-wide `mc event remove minio/ids-pipeline --force`). Debug mc
from inside the cluster: `kubectl run mcdbg -n tig-airflow --rm -i --restart=Never --image=minio/mc:RELEASE.2024-11-21T17-21-54Z --command -- sh -c 'mc alias set minio http://minio.tig-airflow.svc.cluster.local:9000 minioadmin minioadmin; mc event list minio/ids-pipeline'`.

## Evidence checklist
- `kubectl logs job/ids-seed -n tig-airflow`: `Successfully added arn:minio:sqs::RABBITMQ:amqp`, `Filter: suffix=".VIC"`, two `mc cp` lines.
- RabbitMQ UI http://localhost:15672 (guest/guest) `#/queues/%2F/ids-fdr-queue`: Ready=2 before the listener, 0 + Consumers=1 after. "Get messages" (Nack requeue) shows the MinIO `s3:ObjectCreated:Put` payload. "Publish message" with a non-JSON body should yield `✗ Malformed event, rejecting` in listener logs and no redelivery.
- Listener startup log must show `AMQP: amqp://guest:***@...` (password redacted).
- Intermediate RAS uploads under `processque/<run_id>/` also produce `.VIC` events; the listener logs `No process match ... skipping` — expected, not a bug.
- Airflow http://localhost:8080 (admin/admin) `/dags/ids_terrain_ncam/grid`; MinIO console http://localhost:9001 (minioadmin/minioadmin) `/browser/ids-pipeline`.
- Success outputs: 10 objects under `output/sol/01835/ids/rdr/ncam/` (L+R `.obj` ~55 MiB, `.iv` ~45 MiB, `.mtl`, `.png` ~750 KiB, `.lbl`). The MinIO console "Preview" of the `.png` should show real NavCam terrain — a quick visual proof the data was genuine.
- Task logs live on the node: `docker exec minikube tail -40 /mnt/airflow-logs/dag_id=ids_terrain_ncam/run_id=*<runid-suffix>/task_id=<task>/attempt=1.log`.
