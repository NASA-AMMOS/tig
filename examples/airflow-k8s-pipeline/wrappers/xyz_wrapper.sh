#!/bin/bash
# Wrapper for XYZ generation (marsxyz + marsrfilt + m20filter + marsfilter + marsmask), per eye.
#
# The DAG passes the RAS pair already ordered for THIS eye:
#   xyz_left : FIRST=left  SECOND=right  DISP=left-disparity  -> left XYM
#   xyz_right: FIRST=right SECOND=left   DISP=right-disparity -> right XYM
# marsxyz is fed the pair in the ORDER RECEIVED (first = this eye's camera).
set -e

# Args: <s3_endpoint> <bucket> <first_ras_key> <second_ras_key> <disparity_key> <xym_output_key> <run_id> <eye>
S3_ENDPOINT="$1"
BUCKET="$2"
FIRST_RAS_KEY="$3"
SECOND_RAS_KEY="$4"
DISPARITY_KEY="$5"
XYM_OUTPUT_KEY="$6"
RUN_ID="$7"
EYE="$8"  # "left" or "right"

export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-west-2
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib

WORKDIR="/tmp/work/${RUN_ID}/xyz_${EYE}"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "=== xyz wrapper (${EYE} eye) ==="
echo "First RAS:  s3://${BUCKET}/${FIRST_RAS_KEY}"
echo "Second RAS: s3://${BUCKET}/${SECOND_RAS_KEY}"
echo "Disparity:  s3://${BUCKET}/${DISPARITY_KEY}"
echo "XYM out:    s3://${BUCKET}/${XYM_OUTPUT_KEY}"

# Download inputs (named by pair position; first.vic is THIS eye's camera)
echo "Downloading inputs..."
aws --endpoint-url="$S3_ENDPOINT" s3 cp "s3://${BUCKET}/${FIRST_RAS_KEY}" first.vic
aws --endpoint-url="$S3_ENDPOINT" s3 cp "s3://${BUCKET}/${SECOND_RAS_KEY}" second.vic
aws --endpoint-url="$S3_ENDPOINT" s3 cp "s3://${BUCKET}/${DISPARITY_KEY}" disparity.img

# marsxyz — pair in order received (first = this eye). Exits non-zero on success; check file.
echo "Running marsxyz..."
marsxyz \( first.vic second.vic \) pointcloud.xyz disp=disparity.img \
  error=0.05 abserr=0.15 lined=4000 avgline=20 zlimit=\(-300 300\) spike_range=0.04 outlier=0.5 || true
if [ ! -f pointcloud.xyz ]; then
  echo "✗ ERROR: marsxyz (${EYE}) produced no pointcloud.xyz"
  exit 1
fi

# marsrfilt (rover hardware filter)
echo "Running marsrfilt (rover hardware filter)..."
marsrfilt inp=pointcloud.xyz out=pointcloud_filtered.xyz || {
  echo "⚠ marsrfilt failed, using unfiltered XYZ"
  cp pointcloud.xyz pointcloud_filtered.xyz
}

# m20filter (kinematic mask) uses THIS eye's camera image = first.vic, then marsfilter + marsmask.
# Fallbacks at each step guarantee pointcloud_masked.xym always exists (matches demo).
echo "Running m20filter (kinematic mask)..."
m20filter inp=first.vic out=m20_mask.xml || true

if [ ! -f m20_mask.xml ]; then
  echo "⚠ m20filter failed, skipping kinematic masking"
  cp pointcloud_filtered.xyz pointcloud_masked.xym
else
  echo "Applying mask to XYZ (marsfilter)..."
  marsfilter inp=pointcloud_filtered.xyz out=mask_image.img extra=m20_mask.xml || true
  if [ ! -f mask_image.img ]; then
    echo "⚠ marsfilter failed, skipping masking"
    cp pointcloud_filtered.xyz pointcloud_masked.xym
  else
    echo "Creating masked point cloud (marsmask)..."
    marsmask inp=pointcloud_filtered.xyz out=pointcloud_masked.xym mask=mask_image.img || true
    if [ ! -f pointcloud_masked.xym ]; then
      echo "⚠ marsmask failed, using unmasked XYZ"
      cp pointcloud_filtered.xyz pointcloud_masked.xym
    fi
  fi
fi

# Upload per-eye XYM
echo "Uploading XYM..."
aws --endpoint-url="$S3_ENDPOINT" s3 cp pointcloud_masked.xym "s3://${BUCKET}/${XYM_OUTPUT_KEY}"

echo "✓ xyz complete (${EYE} eye)"
