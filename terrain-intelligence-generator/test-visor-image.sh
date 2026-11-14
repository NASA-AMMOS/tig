#!/bin/bash
#
# test-visor-image.sh - Smoke tests for a VISOR calibration image variant
#
# Complements test-docker-image.sh, which asserts the opposite about the base
# image: that no VISOR data is bundled there.
#
# Usage:
#   ./test-visor-image.sh <image-tag>
#
# Example:
#   ./test-visor-image.sh terrain-intelligence-generator:visor-msl
#
# For the msl variant the script also runs marsrad, a MARS tool that cannot
# work without calibration, on a real MSL Navcam EDR pulled out of the VISOR
# sample data. That is the only mission the published sample data covers, so
# for the others the run is reported as skipped rather than silently dropped.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ $# -eq 0 ]; then
    echo "Usage: $0 <image-tag>"
    exit 1
fi

IMAGE_TAG="$1"
CALIB_ROOT="/usr/local/vicar/mars_calib"
SAMPLE_URL="https://github.com/NASA-AMMOS/VICAR/releases/download/5.0/visor_sample_data_20230623.tar.gz"
SAMPLE_MEMBER="sample_data/RadiometricCorrection/NLB_712299404EDR_F0961766NCAM00353M1.IMG"
TESTS_PASSED=0
TESTS_FAILED=0
STATUS=0

PLATFORM_FLAG="--platform linux/amd64"

# Enforcing SELinux otherwise denies the container the bind mounts below. Same
# flag, and same choice of it over ':z'/':Z' relabeling, as the tig CLI.
SELINUX_FLAG=""
if command -v getenforce > /dev/null 2>&1 && [ "$(getenforce)" = "Enforcing" ]; then
    SELINUX_FLAG="--security-opt label=disable"
fi

TEST_WORKSPACE=$(mktemp -d)
trap 'rm -rf "${TEST_WORKSPACE}"' EXIT

print_test_header() {
    echo ""
    echo "============================================"
    echo "$1"
    echo "============================================"
}

# Each check runs as `check ... ; test_result $STATUS ...` rather than as a
# bare command, so that a failing check is recorded and the remaining checks
# still run instead of set -e killing the script.
check() {
    STATUS=0
    "$@" || STATUS=$?
}

test_result() {
    if [ "$1" -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ ERROR: $2${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo -e "${BLUE}Testing VISOR variant image: ${IMAGE_TAG}${NC}"

MISSIONS=$(docker run --rm ${PLATFORM_FLAG} "${IMAGE_TAG}" bash -c 'echo $VISOR_MISSIONS')
if [ -z "${MISSIONS}" ]; then
    echo -e "${RED}✗ ERROR: VISOR_MISSIONS is not set; this is not a VISOR variant image${NC}"
    exit 1
fi
echo -e "${BLUE}Bundled missions: ${MISSIONS}${NC}"

# Test 1: calibration is bundled, with the structure MARS tools expect
print_test_header "Test 1: Calibration present for every bundled mission"
check docker run --rm ${PLATFORM_FLAG} "${IMAGE_TAG}" bash -c '
    status=0
    for mission in $VISOR_MISSIONS; do
        dir="'"${CALIB_ROOT}"'/$mission"
        models=$(ls "$dir/camera_models" 2>/dev/null | wc -l)
        params=$(ls "$dir/param_files" 2>/dev/null | wc -l)
        echo "  $mission: $models camera models, $params parameter files, $(du -sh "$dir" | cut -f1)"
        if [ "$models" -eq 0 ] || [ "$params" -eq 0 ]; then
            status=1
        fi
    done
    exit $status
'
test_result $STATUS "Calibration bundled for every mission in VISOR_MISSIONS"

# Test 2: the tools are pointed at it without the user configuring anything
print_test_header "Test 2: MARS_CONFIG_PATH baked into the image"
check docker run --rm ${PLATFORM_FLAG} "${IMAGE_TAG}" bash -c '
    echo "  MARS_CONFIG_PATH=$MARS_CONFIG_PATH"
    [ -n "$MARS_CONFIG_PATH" ] || exit 1
    for mission in $VISOR_MISSIONS; do
        case ":$MARS_CONFIG_PATH:" in
            *":'"${CALIB_ROOT}"'/$mission:"*) ;;
            *) echo "  $mission missing from MARS_CONFIG_PATH"; exit 1;;
        esac
    done
'
test_result $STATUS "MARS_CONFIG_PATH covers every bundled mission"

# Test 3: the compressed archives must not survive into the image
print_test_header "Test 3: No calibration archives left in the image"
check docker run --rm ${PLATFORM_FLAG} "${IMAGE_TAG}" bash -c '
    found=$(find / -xdev -name "visor_*.tar.gz*" 2>/dev/null)
    if [ -n "$found" ]; then
        echo "$found"
        exit 1
    fi
'
test_result $STATUS "Downloaded archives deleted in the layer that extracted them"

# Test 4: a user-supplied calibration mount must fully replace the bundled
# data, not merge with it
print_test_header "Test 4: Mounted calibration overrides the bundled data"
mkdir -p "${TEST_WORKSPACE}/calib/param_files"
touch "${TEST_WORKSPACE}/calib/param_files/OVERRIDE_marker"
check docker run --rm ${PLATFORM_FLAG} ${SELINUX_FLAG} \
    -v "${TEST_WORKSPACE}/calib:${CALIB_ROOT}:ro" \
    "${IMAGE_TAG}" bash -c '
    [ -f "'"${CALIB_ROOT}"'/param_files/OVERRIDE_marker" ] || exit 1
    for mission in $VISOR_MISSIONS; do
        if [ -d "'"${CALIB_ROOT}"'/$mission" ]; then
            echo "  bundled $mission still visible under the mount"
            exit 1
        fi
    done
'
test_result $STATUS "Mount at ${CALIB_ROOT} shadows the bundled calibration"

# Test 5: a MARS tool that cannot run without calibration actually runs
print_test_header "Test 5: MARS tool using the bundled calibration"
if ! echo " ${MISSIONS} " | grep -q " msl "; then
    echo -e "${YELLOW}⚠ Skipped: the VISOR sample data only covers msl and mer,"
    echo -e "  and no mer product in it needs calibration. Bundled: ${MISSIONS}${NC}"
else
    echo "Fetching one MSL Navcam EDR from the VISOR sample data..."
    # --occurrence stops tar at the first match, which closes the pipe and
    # ends the download early instead of pulling all 740MB. curl then reports
    # a write failure, which is the expected outcome, not an error.
    ( cd "${TEST_WORKSPACE}" && curl --proto '=https' --proto-redir '=https' -fsSL "${SAMPLE_URL}" 2>/dev/null \
        | tar -xz --occurrence=1 "${SAMPLE_MEMBER}" ) || true
    SAMPLE="${TEST_WORKSPACE}/${SAMPLE_MEMBER}"
    if [ ! -f "${SAMPLE}" ]; then
        test_result 1 "Could not fetch the sample MSL EDR"
    else
        mkdir -p "${TEST_WORKSPACE}/run"
        cp "${SAMPLE}" "${TEST_WORKSPACE}/run/edr.IMG"
        check docker run --rm ${PLATFORM_FLAG} ${SELINUX_FLAG} \
            -v "${TEST_WORKSPACE}/run:/workspace" \
            "${IMAGE_TAG}" bash -c '
            cd /workspace
            marsrad edr.IMG rad.IMG > marsrad.log 2>&1
            grep -q "Successfully read calibration camera model" marsrad.log || {
                echo "  marsrad did not load a calibration camera model:"
                tail -20 marsrad.log
                exit 1
            }
            grep -q "path='"${CALIB_ROOT}"'/msl/" marsrad.log || {
                echo "  the camera model did not come from the bundled calibration:"
                grep "path=" marsrad.log
                exit 1
            }
            [ -s rad.IMG ]
        '
        test_result $STATUS "marsrad radiometrically corrected an MSL EDR with no calibration mounted"
    fi
fi

echo ""
echo "============================================"
echo "TEST SUMMARY"
echo "============================================"
echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    echo ""
    echo -e "${RED}✗ TESTS FAILED${NC}"
    exit 1
fi
echo -e "${GREEN}Failed: 0${NC}"
echo ""
echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
