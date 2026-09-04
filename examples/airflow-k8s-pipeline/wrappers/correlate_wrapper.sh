#!/bin/bash
# Wrapper for stereo correlation (marsecorr + marscor3), per direction.
#
# The DAG passes the RAS pair already in the correct order for this direction:
#   correlate_left  (l2r): FIRST=left  SECOND=right -> refined disparity for left eye
#   correlate_right (r2l): FIRST=right SECOND=left  -> refined disparity for right eye
# We feed the pair to marsecorr/marscor3 in the ORDER RECEIVED (do NOT hardcode).
set -e

# Args: <s3_endpoint> <bucket> <first_ras_key> <second_ras_key> <disparity_output_key> <run_id> <eye>
S3_ENDPOINT="$1"
BUCKET="$2"
FIRST_RAS_KEY="$3"
SECOND_RAS_KEY="$4"
DISPARITY_OUTPUT_KEY="$5"
RUN_ID="$6"
EYE="$7"  # "left" or "right"

export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-west-2
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib

WORKDIR="/tmp/work/${RUN_ID}/correlate_${EYE}"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "=== correlate wrapper (${EYE} eye) ==="
echo "First RAS:  s3://${BUCKET}/${FIRST_RAS_KEY}"
echo "Second RAS: s3://${BUCKET}/${SECOND_RAS_KEY}"
echo "Disparity out: s3://${BUCKET}/${DISPARITY_OUTPUT_KEY}"

# Download RAS inputs (named by pair position, not by eye)
echo "Downloading inputs..."
aws --endpoint-url="$S3_ENDPOINT" s3 cp "s3://${BUCKET}/${FIRST_RAS_KEY}" first.vic
aws --endpoint-url="$S3_ENDPOINT" s3 cp "s3://${BUCKET}/${SECOND_RAS_KEY}" second.vic

# marsecorr (initial disparity seed) - may exit non-zero even on success (exit<=1 ok)
echo "Running marsecorr (initial correlation)..."
marsecorr inp=\( first.vic second.vic \) out=disparity_init.img -STAT pyrlevel=1 search=4 band=2 min_range=0.25 || true

# marscor3 (refinement). Per demo semantics marscor3 exits 1 EXACTLY on success.
echo "Running marscor3 (refinement)..."
marscor3 \( first.vic second.vic \) disparity.img \
  in_disp=disparity_init.img \
  template=11 search=31 quality=0.6 \
  -gores gore_q=0.6 gore_pass=5 -gore_rev \
  disp_pyr=1 -amoeba ftol=.001 band=2 \
  -multipass -GAUSSFILTER -SCALING -DECIMATION -TILING -STAT \
  -omp_on SCALING_THRESH=1 || true

# disparity.img is required downstream - hard fail if not produced
if [ ! -f disparity.img ]; then
  echo "✗ ERROR: correlation (${EYE}) failed to produce disparity.img"
  exit 1
fi

# Upload per-eye disparity
echo "Uploading disparity..."
aws --endpoint-url="$S3_ENDPOINT" s3 cp disparity.img "s3://${BUCKET}/${DISPARITY_OUTPUT_KEY}"

echo "✓ correlate (${EYE}) complete"
