#!/bin/bash
#
# test-docker-image.sh - Comprehensive test suite for VICAR Docker image
#
# This script runs the same tests as the GitHub Actions workflow, allowing
# developers to test locally before pushing.
#
# Usage:
#   ./test-docker-image.sh <image-tag>
#
# Example:
#   ./test-docker-image.sh tig-vicar-test:latest
#   ./test-docker-image.sh ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <image-tag>"
    echo "Example: $0 tig-vicar-test:latest"
    exit 1
fi

IMAGE_TAG="$1"
TESTS_PASSED=0
TESTS_FAILED=0

# Detect platform and set Docker platform flag if needed
PLATFORM_FLAG=""
if [[ "$(uname -m)" == "arm64" ]] || [[ "$(uname -m)" == "aarch64" ]]; then
    PLATFORM_FLAG="--platform linux/amd64"
    echo -e "${YELLOW}Detected ARM architecture, using platform flag: linux/amd64${NC}"
fi

# Create temporary workspace for testing
TEST_WORKSPACE=$(mktemp -d)
echo -e "${BLUE}Created test workspace: ${TEST_WORKSPACE}${NC}"
echo ""

# Function to print test header
print_test_header() {
    echo ""
    echo "============================================"
    echo "$1"
    echo "============================================"
}

# Function to handle test result
test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ ERROR: $2${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

echo -e "${BLUE}Testing image: ${IMAGE_TAG}${NC}"

# Test 1: Container startup
print_test_header "Test 1: Container startup"
if docker run --rm ${PLATFORM_FLAG} ${IMAGE_TAG} echo "Container started successfully" > /dev/null 2>&1; then
    test_result 0 "Container starts successfully"
else
    test_result 1 "Container failed to start"
    exit 1
fi

# Test 2: Directory structure verification
print_test_header "Test 2: Directory structure (flattening)"
docker run --rm ${PLATFORM_FLAG} ${IMAGE_TAG} bash -c '
    echo "Checking V2TOP structure..."
    if [ -d "$V2TOP/p2/lib/x86-64-linx" ] && [ -d "$V2TOP/tae53/bin" ] && [ -d "$V2TOP/mars/lib/x86-64-linx" ]; then
        P2_COUNT=$(find $V2TOP/p2/lib/x86-64-linx -type f -executable 2>/dev/null | wc -l)
        TAE_COUNT=$(find $V2TOP/tae53/bin -type f -executable 2>/dev/null | wc -l)
        MARS_COUNT=$(find $V2TOP/mars/lib/x86-64-linx -type f -executable 2>/dev/null | wc -l)
        echo "  p2: $P2_COUNT programs"
        echo "  tae53: $TAE_COUNT programs"
        echo "  mars: $MARS_COUNT programs"
        exit 0
    else
        exit 1
    fi
'
test_result $? "Directory structure is correctly flattened"

# Test 3: Environment variables
print_test_header "Test 3: Environment variables"
docker run --rm ${PLATFORM_FLAG} ${IMAGE_TAG} bash -c '
    echo "V2TOP=$V2TOP"
    echo "WORKSPACE=$WORKSPACE"
    echo "VICSYS=$VICSYS"
    echo "VISOR_CALIB=$VISOR_CALIB"
    echo "VISOR_SAMPLES=$VISOR_SAMPLES"
    
    if [ -z "$V2TOP" ] || [ -z "$WORKSPACE" ] || [ -z "$VICSYS" ]; then
        exit 1
    fi
'
test_result $? "All environment variables set correctly"

# Test 4: Wrapper scripts
print_test_header "Test 4: Wrapper scripts"
docker run --rm ${PLATFORM_FLAG} ${IMAGE_TAG} bash -c '
    WRAPPER_COUNT=$(ls -1 /usr/local/bin | wc -l)
    echo "Total wrapper scripts: $WRAPPER_COUNT"
    
    # Check for key commands
    for cmd in gen list copy stretch marsmap marsmos vicario; do
        if [ ! -x "/usr/local/bin/$cmd" ]; then
            echo "Missing: $cmd"
            exit 1
        fi
    done
    
    # Verify wrapper script format
    if ! grep -q "export V2TOP" /usr/local/bin/gen || ! grep -q "export LD_LIBRARY_PATH" /usr/local/bin/gen; then
        exit 1
    fi
'
test_result $? "Wrapper scripts exist and have correct format"

# Test 5: Generate test image
print_test_header "Test 5: Generate test image (gen command)"
docker run --rm -v ${TEST_WORKSPACE}:/workspace ${IMAGE_TAG} bash -c '
    gen /workspace/test.vic 256 256 > /dev/null 2>&1
    if [ -f /workspace/test.vic ]; then
        SIZE=$(stat -f%z /workspace/test.vic 2>/dev/null || stat -c%s /workspace/test.vic 2>/dev/null)
        echo "Generated test.vic ($SIZE bytes)"
        exit 0
    else
        exit 1
    fi
'
test_result $? "gen command successful"

# Test 6: List image contents
print_test_header "Test 6: List image contents (list command)"
docker run --rm -v ${TEST_WORKSPACE}:/workspace ${IMAGE_TAG} list /workspace/test.vic > /dev/null 2>&1
test_result $? "list command successful"

# Test 7: Copy operation
print_test_header "Test 7: Copy image (copy command)"
docker run --rm -v ${TEST_WORKSPACE}:/workspace ${IMAGE_TAG} bash -c '
    copy /workspace/test.vic /workspace/test_copy.vic > /dev/null 2>&1
    [ -f /workspace/test_copy.vic ]
'
test_result $? "copy command successful"

# Test 8: Stretch operation
print_test_header "Test 8: Stretch image (stretch command)"
docker run --rm -v ${TEST_WORKSPACE}:/workspace ${IMAGE_TAG} bash -c '
    stretch /workspace/test.vic /workspace/stretched.vic > /dev/null 2>&1
    [ -f /workspace/stretched.vic ]
'
test_result $? "stretch command successful"

# Test 9: vicario converter (PNG)
print_test_header "Test 9: vicario converter (VICAR to PNG)"
docker run --rm -v ${TEST_WORKSPACE}:/workspace ${IMAGE_TAG} bash -c '
    vicario /workspace/test.vic /workspace/test.png > /dev/null 2>&1
    [ -f /workspace/test.png ]
'
test_result $? "PNG conversion successful"

# Test 10: vicario converter (JPEG)
print_test_header "Test 10: vicario converter (VICAR to JPEG)"
docker run --rm -v ${TEST_WORKSPACE}:/workspace ${IMAGE_TAG} bash -c '
    vicario /workspace/test.vic /workspace/test.jpg > /dev/null 2>&1
    [ -f /workspace/test.jpg ]
'
test_result $? "JPEG conversion successful"

# Test 11: VISOR sample data access
print_test_header "Test 11: VISOR sample data"
docker run --rm ${PLATFORM_FLAG} ${IMAGE_TAG} bash -c '
    if [ -d "$VISOR_SAMPLES" ]; then
        SAMPLE_COUNT=$(find $VISOR_SAMPLES -type f 2>/dev/null | wc -l)
        echo "VISOR sample data: $SAMPLE_COUNT files"
    else
        exit 1
    fi
    
    if [ -d "$VISOR_CALIB" ]; then
        CALIB_COUNT=$(find $VISOR_CALIB -type f 2>/dev/null | wc -l)
        echo "VISOR calibration data: $CALIB_COUNT files"
    else
        exit 1
    fi
'
test_result $? "VISOR data accessible"

# Test 12: Python and dependencies
print_test_header "Test 12: Python and dependencies"
docker run --rm ${PLATFORM_FLAG} ${IMAGE_TAG} bash -c '
    python3 --version
    python3 -c "import PIL; print(f\"Pillow {PIL.__version__}\")"
' > /dev/null 2>&1
test_result $? "Python and Pillow available"

# Test 13: Docker exec pattern
print_test_header "Test 13: Docker exec pattern (long-running container)"
docker run -d --name vicar-test-container -v ${TEST_WORKSPACE}:/workspace ${IMAGE_TAG} tail -f /dev/null > /dev/null 2>&1
sleep 2

if ! docker exec vicar-test-container gen /workspace/exec_test.vic 128 128 > /dev/null 2>&1; then
    echo -e "${RED}gen command failed${NC}"
    docker stop vicar-test-container > /dev/null 2>&1
    docker rm vicar-test-container > /dev/null 2>&1
    test_result 1 "Docker exec pattern failed (gen)"
elif ! docker exec vicar-test-container list /workspace/exec_test.vic > /dev/null 2>&1; then
    echo -e "${RED}list command failed${NC}"
    docker stop vicar-test-container > /dev/null 2>&1
    docker rm vicar-test-container > /dev/null 2>&1
    test_result 1 "Docker exec pattern failed (list)"
elif ! docker exec vicar-test-container vicario /workspace/exec_test.vic /workspace/exec_test.png > /dev/null 2>&1; then
    echo -e "${RED}vicario command failed${NC}"
    docker stop vicar-test-container > /dev/null 2>&1
    docker rm vicar-test-container > /dev/null 2>&1
    test_result 1 "Docker exec pattern failed (vicario)"
elif docker exec vicar-test-container test -f /workspace/exec_test.png; then
    test_result 0 "Docker exec pattern works correctly"
    docker stop vicar-test-container > /dev/null 2>&1
    docker rm vicar-test-container > /dev/null 2>&1
else
    echo -e "${RED}output file not created${NC}"
    docker stop vicar-test-container > /dev/null 2>&1
    docker rm vicar-test-container > /dev/null 2>&1
    test_result 1 "Docker exec pattern failed (file not created)"
fi

# Test 14: File persistence verification
print_test_header "Test 14: File persistence to host"
EXPECTED_FILES="test.vic test_copy.vic stretched.vic test.png test.jpg exec_test.vic exec_test.png"
ALL_FOUND=true
for file in $EXPECTED_FILES; do
    if [ -f "${TEST_WORKSPACE}/${file}" ]; then
        echo -e "${GREEN}✓${NC} ${file} exists on host"
    else
        echo -e "${RED}✗${NC} ${file} not found on host"
        ALL_FOUND=false
    fi
done

if [ "$ALL_FOUND" = true ]; then
    test_result 0 "All files persisted to host"
else
    test_result 1 "Some files missing on host"
fi

# Test 15: MARS commands availability
print_test_header "Test 15: MARS commands availability"
docker run --rm ${PLATFORM_FLAG} ${IMAGE_TAG} bash -c '
    MARS_COUNT=$(ls /usr/local/bin | grep -c "^mars")
    echo "MARS commands available: $MARS_COUNT"
    
    # Check for key MARS commands
    for cmd in marsmap marsmos marsautotie marscor3; do
        if [ ! -x "/usr/local/bin/$cmd" ]; then
            exit 1
        fi
    done
'
test_result $? "MARS commands available"

# Cleanup
rm -rf ${TEST_WORKSPACE}
echo ""

# Final summary
echo "============================================"
echo "TEST SUMMARY"
echo "============================================"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo ""
    echo -e "${RED}✗ TESTS FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}Failed: 0${NC}"
    echo ""
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    exit 0
fi
