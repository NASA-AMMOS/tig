#!/bin/bash
# Wrapper for mesh generation (marsmesh + vicario), per eye.
#
# The DAG passes the per-eye RAS basename so marsmesh names all sibling products
# (.obj/.mtl/.lbl/.iv) with the proper M20 RAS product name, and the .obj's
# internal mtllib/usemtl references resolve to <RAS_BASE>.mtl. Mesh outputs keep
# the RAS token (e.g. NLM_..._M777RAS_....obj), matching reference fixtures.
set -e

# Args: <s3_endpoint> <bucket> <xym_key> <ras_key> <ods_prefix> <ras_base> <run_id> <eye>
S3_ENDPOINT="$1"
BUCKET="$2"
XYM_KEY="$3"
RAS_KEY="$4"        # this eye's RAS image (texture skin)
ODS_PREFIX="$5"     # e.g. output/sol/01835/ids/rdr/ncam
RAS_BASE="$6"       # e.g. NLM_1835_0829848458M777RAS_N0874924NCAM00230_0A02LLJ01
RUN_ID="$7"
EYE="$8"  # "left" or "right"

export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-west-2
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib

WORKDIR="/tmp/work/${RUN_ID}/mesh_${EYE}"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "=== mesh wrapper (${EYE} eye) ==="
echo "XYM:  s3://${BUCKET}/${XYM_KEY}"
echo "RAS:  s3://${BUCKET}/${RAS_KEY}"
echo "Out:  s3://${BUCKET}/${ODS_PREFIX}/${RAS_BASE}.{obj,mtl,png,lbl,iv}"

# Download inputs
echo "Downloading inputs..."
aws --endpoint-url="$S3_ENDPOINT" s3 cp "s3://${BUCKET}/${XYM_KEY}" pointcloud.xym
aws --endpoint-url="$S3_ENDPOINT" s3 cp "s3://${BUCKET}/${RAS_KEY}" "${RAS_BASE}.VIC"

# marsmesh — out named by RAS_BASE so .obj/.mtl/.lbl/.iv siblings all inherit it,
# and the .obj mtllib/usemtl point at ${RAS_BASE}.mtl. Per demo, marsmesh exits 1
# EXACTLY on success; we check .obj existence instead of trusting the exit code.
echo "Running marsmesh..."
marsmesh inp=pointcloud.xym out="${RAS_BASE}.obj" in_skin="${RAS_BASE}.VIC" \
  x_subsample=1 y_subsample=1 \
  range_min=0.2 range_mid=100 range_max=100 \
  lod_levels=10 max_angle=87.5 \
  res_min=3000 res_max=500000 density=1 \
  -adaptive || true

# .obj is the required output - hard fail if not produced
if [ ! -f "${RAS_BASE}.obj" ]; then
  echo "✗ ERROR: marsmesh (${EYE}) failed to produce ${RAS_BASE}.obj"
  exit 1
fi

# vicario (texture conversion) -> <RAS_BASE>.png ; tolerant of non-zero exit
echo "Running vicario (texture conversion)..."
vicario "${RAS_BASE}.VIC" "${RAS_BASE}.png" || true

# Upload outputs. .obj required; .mtl/.png/.lbl/.iv conditional (best-effort).
echo "Uploading outputs..."
aws --endpoint-url="$S3_ENDPOINT" s3 cp "${RAS_BASE}.obj" "s3://${BUCKET}/${ODS_PREFIX}/${RAS_BASE}.obj"
for ext in mtl png lbl iv; do
  if [ -f "${RAS_BASE}.${ext}" ]; then
    aws --endpoint-url="$S3_ENDPOINT" s3 cp "${RAS_BASE}.${ext}" "s3://${BUCKET}/${ODS_PREFIX}/${RAS_BASE}.${ext}"
  else
    echo "⚠ ${RAS_BASE}.${ext} not produced, skipping"
  fi
done

# Optional .glb (best-effort). The VICAR image also ships an unrelated `obj2gltf`
# TAE program that rejects these args, so failures here are non-fatal.
if command -v obj2gltf &> /dev/null; then
  echo "Generating .glb (best-effort)..."
  if obj2gltf -i "${RAS_BASE}.obj" -o "${RAS_BASE}.glb" > /dev/null 2>&1 && [ -f "${RAS_BASE}.glb" ]; then
    aws --endpoint-url="$S3_ENDPOINT" s3 cp "${RAS_BASE}.glb" "s3://${BUCKET}/${ODS_PREFIX}/${RAS_BASE}.glb"
  else
    echo "⚠ obj2gltf unavailable/incompatible, skipping .glb"
  fi
fi

echo "✓ mesh complete (${EYE} eye): ${RAS_BASE}.obj"
