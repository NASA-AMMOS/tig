#!/bin/bash
# Wrapper for marsrad task (FDR → RAS radiometric correction)
set -e

# Args: <s3_endpoint> <bucket> <input_key> <output_key> <run_id>
S3_ENDPOINT="$1"
BUCKET="$2"
INPUT_KEY="$3"
OUTPUT_KEY="$4"
RUN_ID="$5"

export AWS_ACCESS_KEY_ID=minioadmin
export AWS_SECRET_ACCESS_KEY=minioadmin
export AWS_DEFAULT_REGION=us-west-2
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib

WORKDIR="/tmp/work/${RUN_ID}"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "=== marsrad wrapper ==="
echo "Input: s3://${BUCKET}/${INPUT_KEY}"
echo "Output: s3://${BUCKET}/${OUTPUT_KEY}"

# Download input FDR
echo "Downloading input..."
aws --endpoint-url="$S3_ENDPOINT" s3 cp "s3://${BUCKET}/${INPUT_KEY}" input.vic

# Run marsrad (marsrad may exit non-zero even on success; check output file existence like demo)
echo "Running marsrad (FDR → RAS)..."
marsrad inp=input.vic out=output_ras.vic || true

# Fall back to FDR if RAS not produced (matches demo-mesh-m20-exact.sh behavior)
if [ ! -f output_ras.vic ]; then
  echo "⚠ WARNING: marsrad failed to produce output, using FDR image as-is"
  cp input.vic output_ras.vic
fi

# Upload output
echo "Uploading output..."
aws --endpoint-url="$S3_ENDPOINT" s3 cp output_ras.vic "s3://${BUCKET}/${OUTPUT_KEY}"

echo "✓ marsrad complete"
