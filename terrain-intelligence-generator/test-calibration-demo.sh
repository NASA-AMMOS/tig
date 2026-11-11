#!/bin/bash
#
# test-calibration-demo.sh - Run a demo against real VISOR calibration
#
# Nothing else in CI touches the calibration path: the product tests build a
# synthetic fixture in-image precisely so they need no calibration and no
# download. This runs demo-surface-characteristics.sh the way a user would,
# on a real MSL Navcam XYZ product with the real MSL VISOR calibration
# mounted, and asserts the products came out.
#
# ~1.1 GB of downloads, so it is not for the pull request path.
#
# Usage:
#   ./test-calibration-demo.sh [<image-tag>] [--data-dir DIR] [--keep]
#
# Example:
#   ./test-calibration-demo.sh ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource
#
# --data-dir reuses (and populates) a download directory instead of a
# throwaway one; --keep leaves the workspace behind for inspection.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

IMAGE_TAG="ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource"
DATA_DIR=""
KEEP=false

RELEASE_URL="https://github.com/NASA-AMMOS/VICAR/releases/download/5.0"
CALIB_ASSET="visor_calibration_20230608_msl.tar.gz"
SAMPLE_ASSET="visor_sample_data_20230623.tar.gz"
# The one mission the published sample data covers, and the one product set
# with a matching XYZ cloud and scene image.
XYZ_MEMBER="sample_data/OrthorectifiedMosaic/NLB_712299404XYZ_F0961766NCAM00353M1.IMG"
ILT_MEMBER="sample_data/OrthorectifiedMosaic/NLB_712299404ILT_F0961766NCAM00353M1.IMG"

while [ $# -gt 0 ]; do
    case "$1" in
        --data-dir)
            [ -z "$2" ] && { echo "ERROR: --data-dir requires a DIR"; exit 1; }
            DATA_DIR="$2"; shift 2 ;;
        --keep)
            KEEP=true; shift ;;
        -h|--help)
            sed -n '3,21p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *)
            IMAGE_TAG="$1"; shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEMO="${REPO_ROOT}/demo-surface-characteristics.sh"

print_header() {
    echo ""
    echo "============================================"
    echo "$1"
    echo "============================================"
}

echo -e "${BLUE}Real-calibration demo run against: ${IMAGE_TAG}${NC}"

for cmd in docker tig curl tar; do
    command -v "$cmd" > /dev/null 2>&1 || {
        echo -e "${RED}✗ ${cmd} is required${NC}"
        [ "$cmd" = "tig" ] && echo "  Install it with: pip install tig-cli"
        exit 2
    }
done
[ -f "${DEMO}" ] || { echo -e "${RED}✗ ${DEMO} not found${NC}"; exit 2; }

# Installed before anything is created, so --keep also preserves the log of an
# early failure; a supplied --data-dir is a download cache and is never removed.
CLEANUP_DIRS=()
cleanup() {
    [ "${KEEP}" = true ] && return 0
    [ "${#CLEANUP_DIRS[@]}" -gt 0 ] && rm -rf "${CLEANUP_DIRS[@]}"
    return 0
}
trap cleanup EXIT

if [ -z "${DATA_DIR}" ]; then
    DATA_DIR=$(mktemp -d)
    CLEANUP_DIRS+=("${DATA_DIR}")
fi
mkdir -p "${DATA_DIR}"
# The demo runs from a subdirectory below, where a relative path would not resolve.
DATA_DIR="$(cd "${DATA_DIR}" && pwd)"

print_header "Step 1: MSL VISOR calibration and sample data"

CALIB_DIR="${DATA_DIR}/calibration/msl"
# A marker written only after the whole stream extracted: tar creates the
# directories and truncated files as it goes, so their presence proves nothing.
if [ -f "${DATA_DIR}/.${CALIB_ASSET}.complete" ]; then
    echo "Reusing calibration in ${CALIB_DIR}"
else
    echo "Downloading ${CALIB_ASSET} (380 MB)..."
    mkdir -p "${DATA_DIR}"
    curl --proto '=https' --proto-redir '=https' -fsSL "${RELEASE_URL}/${CALIB_ASSET}" | tar -xz -C "${DATA_DIR}" || {
        echo -e "${RED}✗ Could not download or extract ${CALIB_ASSET}${NC}"; exit 2; }
    touch "${DATA_DIR}/.${CALIB_ASSET}.complete"
fi
{ [ -d "${CALIB_DIR}/camera_models" ] && [ -d "${CALIB_DIR}/param_files" ]; } || {
    echo -e "${RED}✗ ${CALIB_DIR} is missing camera_models/ or param_files/${NC}"; exit 2; }

XYZ_FILE="${DATA_DIR}/${XYZ_MEMBER}"
ILT_FILE="${DATA_DIR}/${ILT_MEMBER}"
if [ -f "${DATA_DIR}/.${SAMPLE_ASSET}.complete" ]; then
    echo "Reusing sample products in ${DATA_DIR}/sample_data"
else
    echo "Downloading ${SAMPLE_ASSET} (740 MB)..."
    curl --proto '=https' --proto-redir '=https' -fsSL "${RELEASE_URL}/${SAMPLE_ASSET}" | \
        tar -xz -C "${DATA_DIR}" "${XYZ_MEMBER}" "${ILT_MEMBER}" || {
        echo -e "${RED}✗ Could not download or extract ${SAMPLE_ASSET}${NC}"; exit 2; }
    touch "${DATA_DIR}/.${SAMPLE_ASSET}.complete"
fi
for f in "${XYZ_FILE}" "${ILT_FILE}"; do
    [ -s "$f" ] || { echo -e "${RED}✗ $f is missing${NC}"; exit 2; }
done
echo -e "${GREEN}✓ Calibration and real MSL Navcam products in place${NC}"

docker pull "${IMAGE_TAG}" > /dev/null || {
    echo -e "${RED}✗ Could not pull ${IMAGE_TAG}${NC}"; exit 2; }

print_header "Step 2: demo-surface-characteristics.sh on real data"

# A fresh directory per run: a warm container from a previous run still holds
# the old bind mount, so reusing the path silently loses the outputs.
RUN_DIR=$(mktemp -d "${DATA_DIR}/run.XXXXXX")
CLEANUP_DIRS+=("${RUN_DIR}")
DEMO_LOG="${RUN_DIR}/demo.log"

set +e
(
    cd "${RUN_DIR}" || exit 1
    MARS_CONFIG_PATH="${CALIB_DIR}" CONTAINER_IMAGE="${IMAGE_TAG}" \
        "${DEMO}" --xyz "${XYZ_FILE}" --texture "${ILT_FILE}"
) > "${DEMO_LOG}" 2>&1
DEMO_STATUS=$?
set -e

grep -E "Using calibration from|Successfully read calibration camera model|abended" \
    "${DEMO_LOG}" | head -5 || true

if [ "${DEMO_STATUS}" -ne 0 ]; then
    echo -e "${RED}✗ The demo exited ${DEMO_STATUS}${NC}"
    tail -30 "${DEMO_LOG}"
    exit 1
fi

print_header "Step 3: The products the demo claims"

FAILED=0
WS="${RUN_DIR}/workspace"

# The point of the run: a camera model was read out of the mounted
# calibration, not out of the image.
if grep -q "Successfully read calibration camera model" "${DEMO_LOG}"; then
    echo -e "${GREEN}✓ A calibration camera model was read${NC}"
else
    echo -e "${RED}✗ No calibration camera model was read${NC}"; FAILED=1
fi

# 1024x1024 REAL products are ~4 MB; a stub or an all-zero raster is not.
for product in slope.img heading.img ntilt.img roughness.img; do
    size=$(wc -c < "${WS}/${product}" 2>/dev/null | tr -d ' ')
    size=${size:-0}
    if [ "${size}" -gt 4000000 ]; then
        echo -e "${GREEN}✓ ${product} (${size} bytes)${NC}"
    else
        echo -e "${RED}✗ ${product} is missing or too small (${size} bytes)${NC}"; FAILED=1
    fi
done

for product in normals_slope.uvw normals_arm.uvw tilt_heli.img goodness_heli.img; do
    if [ -s "${WS}/${product}" ]; then
        echo -e "${GREEN}✓ ${product} ($(wc -c < "${WS}/${product}" | tr -d ' ') bytes)${NC}"
    else
        echo -e "${RED}✗ ${product} is missing${NC}"; FAILED=1
    fi
done

# The PNGs are the only human-checkable output, and an empty raster still
# converts, so assert the slope image has real variation in it.
STDDEV=$(cd "${WS}" && CONTAINER_IMAGE="${IMAGE_TAG}" MARS_CONFIG_PATH="${CALIB_DIR}" \
    tig hist slope.img 2>&1 | grep -oE 'STANDARD DEVIATION=[0-9.]+' | cut -d= -f2 | head -1)
if [ -n "${STDDEV}" ] && awk -v s="${STDDEV}" 'BEGIN { exit !(s > 0.5) }'; then
    echo -e "${GREEN}✓ slope.img varies (standard deviation ${STDDEV} degrees)${NC}"
else
    echo -e "${RED}✗ slope.img has no variation (standard deviation '${STDDEV}')${NC}"; FAILED=1
fi

# marsirough is expected to abend here: see test-marsirough-abend.sh. Report
# it so this run does not quietly become the place that hides it.
if grep -q "marsirough abended" "${DEMO_LOG}"; then
    echo -e "${YELLOW}⚠ marsirough abended, as documented (test-marsirough-abend.sh)${NC}"
fi

print_header "Result"

if [ "${FAILED}" -eq 0 ]; then
    echo -e "${GREEN}✅ Real-calibration demo produced its products${NC}"
    echo "  Image:       ${IMAGE_TAG}"
    echo "  Calibration: ${CALIB_ASSET}"
    echo "  Input:       $(basename "${XYZ_MEMBER}")"
else
    echo -e "${RED}❌ Real-calibration demo failed${NC}"
    # The log goes to stdout: on a runner the workspace is gone afterwards.
    echo "  Demo log (${DEMO_LOG}):"
    tail -40 "${DEMO_LOG}"
fi

[ "${KEEP}" = true ] && echo "  Workspace kept: ${WS}"

exit "${FAILED}"
