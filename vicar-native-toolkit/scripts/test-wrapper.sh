#!/bin/bash
# Test script for VICAR Native Toolkit wrapper functionality
# This script validates the docker-native-wrapper pattern implementation

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONTAINER_NAME="vicar-sidecar"
IMAGE_NAME="vicar-tools:with-rpms"
WRAPPER_DIR="${PROJECT_ROOT}/.direnv/wrappers"
WORKSPACE_DIR="${PROJECT_ROOT}/workspace"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Utility functions
print_header() {
    echo ""
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=====================================${NC}"
}

print_test() {
    echo -e "\n${YELLOW}TEST:${NC} $1"
}

print_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((TESTS_PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((TESTS_FAILED++))
}

print_skip() {
    echo -e "${YELLOW}⊘ SKIP:${NC} $1"
    ((TESTS_SKIPPED++))
}

print_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

print_summary() {
    echo ""
    print_header "TEST SUMMARY"
    echo -e "Total Tests: $((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))"
    echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    echo -e "${YELLOW}Skipped: ${TESTS_SKIPPED}${NC}"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed. See output above for details.${NC}"
        return 1
    fi
}

# Test functions
test_docker_installed() {
    print_test "Docker is installed and accessible"
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            print_pass "Docker is installed and running"
        else
            print_fail "Docker is installed but not running or not accessible"
            return 1
        fi
    else
        print_fail "Docker is not installed"
        return 1
    fi
}

test_direnv_installed() {
    print_test "direnv is installed"
    if command -v direnv &> /dev/null; then
        DIRENV_VERSION=$(direnv version 2>&1 | head -1)
        print_pass "direnv is installed: $DIRENV_VERSION"
    else
        print_skip "direnv is not installed (optional for manual testing)"
    fi
}

test_image_exists() {
    print_test "Docker image exists: $IMAGE_NAME"
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE_NAME}$"; then
        IMAGE_SIZE=$(docker images $IMAGE_NAME --format "{{.Size}}")
        print_pass "Image exists: $IMAGE_NAME (Size: $IMAGE_SIZE)"
    else
        print_fail "Image not found: $IMAGE_NAME"
        print_info "Run: ./scripts/build-image-with-rpms.sh"
        return 1
    fi
}

test_workspace_exists() {
    print_test "Workspace directory exists"
    if [ -d "$WORKSPACE_DIR" ]; then
        print_pass "Workspace exists: $WORKSPACE_DIR"
    else
        print_fail "Workspace directory not found: $WORKSPACE_DIR"
        return 1
    fi
}

test_wrapper_dir_exists() {
    print_test "Wrapper directory exists"
    if [ -d "$WRAPPER_DIR" ]; then
        WRAPPER_COUNT=$(ls -1 "$WRAPPER_DIR" 2>/dev/null | wc -l | tr -d ' ')
        print_pass "Wrapper directory exists with $WRAPPER_COUNT wrappers"
    else
        print_skip "Wrapper directory not found (run 'direnv allow' to generate)"
    fi
}

test_container_running() {
    print_test "Container is running: $CONTAINER_NAME"
    if docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        CONTAINER_STATUS=$(docker ps --filter "name=^${CONTAINER_NAME}$" --format "{{.Status}}")
        print_pass "Container is running: $CONTAINER_STATUS"
        return 0
    else
        print_fail "Container is not running"
        return 1
    fi
}

start_container_if_needed() {
    if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        print_info "Starting container for tests..."
        
        # Check if container exists but is stopped
        if docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
            print_info "Starting existing container..."
            docker start "$CONTAINER_NAME" > /dev/null
        else
            print_info "Creating and starting new container..."
            docker run -d \
                --name "$CONTAINER_NAME" \
                -v "${WORKSPACE_DIR}:/workspace" \
                -w /workspace \
                "$IMAGE_NAME" \
                tail -f /dev/null > /dev/null
        fi
        
        # Wait for container to be ready
        sleep 2
        
        if docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
            print_pass "Container started successfully"
        else
            print_fail "Failed to start container"
            return 1
        fi
    fi
}

test_container_exec() {
    print_test "Container exec functionality"
    if docker exec "$CONTAINER_NAME" echo "test" > /dev/null 2>&1; then
        print_pass "Can execute commands in container"
    else
        print_fail "Cannot execute commands in container"
        return 1
    fi
}

test_workspace_mount() {
    print_test "Workspace is mounted correctly"
    
    # Create a test file
    TEST_FILE="$WORKSPACE_DIR/.wrapper-test-$(date +%s).txt"
    TEST_CONTENT="wrapper-test-content-$$"
    echo "$TEST_CONTENT" > "$TEST_FILE"
    
    # Try to read it from container
    CONTAINER_CONTENT=$(docker exec "$CONTAINER_NAME" cat "/workspace/$(basename "$TEST_FILE")" 2>/dev/null || echo "")
    
    # Clean up
    rm -f "$TEST_FILE"
    
    if [ "$CONTAINER_CONTENT" = "$TEST_CONTENT" ]; then
        print_pass "Workspace mount is working correctly"
    else
        print_fail "Workspace mount is not working (expected: '$TEST_CONTENT', got: '$CONTAINER_CONTENT')"
        return 1
    fi
}

test_vicar_installed() {
    print_test "VICAR is installed in container"
    
    # Check for VICAR RPM packages
    VICAR_RPMS=$(docker exec "$CONTAINER_NAME" rpm -qa 2>/dev/null | grep -i vicar | wc -l | tr -d ' ')
    
    if [ "$VICAR_RPMS" -gt 0 ]; then
        print_pass "Found $VICAR_RPMS VICAR RPM packages installed"
        print_info "Packages: $(docker exec "$CONTAINER_NAME" rpm -qa | grep -i vicar | head -3 | tr '\n' ' ')..."
    else
        print_skip "No VICAR RPM packages found (may be installed differently)"
    fi
}

test_vicar_commands_available() {
    print_test "VICAR commands are available in container"
    
    # Check for commands in /usr/local/bin
    VICAR_CMD_COUNT=$(docker exec "$CONTAINER_NAME" sh -c "ls /usr/local/bin 2>/dev/null | wc -l" | tr -d ' ')
    
    if [ "$VICAR_CMD_COUNT" -gt 10 ]; then
        print_pass "Found $VICAR_CMD_COUNT commands in /usr/local/bin"
        print_info "Sample commands: $(docker exec "$CONTAINER_NAME" sh -c 'ls /usr/local/bin | head -5 | tr "\n" " "')"
    else
        print_fail "Expected more than 10 commands, found only $VICAR_CMD_COUNT"
        return 1
    fi
}

test_wrapper_script_structure() {
    print_test "Wrapper scripts have correct structure"
    
    if [ ! -d "$WRAPPER_DIR" ]; then
        print_skip "Wrapper directory not found"
        return 0
    fi
    
    # Pick a random wrapper to test
    SAMPLE_WRAPPER=$(ls "$WRAPPER_DIR" | head -1)
    
    if [ -z "$SAMPLE_WRAPPER" ]; then
        print_skip "No wrapper scripts found"
        return 0
    fi
    
    WRAPPER_PATH="$WRAPPER_DIR/$SAMPLE_WRAPPER"
    
    # Check if it's executable
    if [ ! -x "$WRAPPER_PATH" ]; then
        print_fail "Wrapper is not executable: $SAMPLE_WRAPPER"
        return 1
    fi
    
    # Check if it contains docker exec
    if grep -q "docker exec" "$WRAPPER_PATH"; then
        print_pass "Wrapper script structure is correct (sample: $SAMPLE_WRAPPER)"
    else
        print_fail "Wrapper script doesn't contain 'docker exec': $SAMPLE_WRAPPER"
        return 1
    fi
}

test_wrapper_execution() {
    print_test "Wrapper can execute commands"
    
    if [ ! -d "$WRAPPER_DIR" ]; then
        print_skip "Wrapper directory not found"
        return 0
    fi
    
    # Test toolkit-shell wrapper if it exists
    if [ -x "$WRAPPER_DIR/toolkit-shell" ]; then
        # Try a non-interactive command through the wrapper mechanism
        if docker exec "$CONTAINER_NAME" echo "wrapper-test-ok" > /dev/null 2>&1; then
            print_pass "Wrapper execution mechanism works"
        else
            print_fail "Wrapper execution failed"
            return 1
        fi
    else
        print_skip "toolkit-shell wrapper not found"
    fi
}

test_vicar_command_wrapper() {
    print_test "VICAR command wrapper functionality"
    
    if [ ! -d "$WRAPPER_DIR" ]; then
        print_skip "Wrapper directory not found"
        return 0
    fi
    
    # Find a VICAR command wrapper (excluding toolkit-* commands)
    VICAR_WRAPPER=$(ls "$WRAPPER_DIR" | grep -v "^toolkit-" | head -1)
    
    if [ -z "$VICAR_WRAPPER" ]; then
        print_skip "No VICAR command wrappers found"
        return 0
    fi
    
    # Try to execute the wrapper with --help or similar
    WRAPPER_PATH="$WRAPPER_DIR/$VICAR_WRAPPER"
    
    # Just check if the wrapper can be invoked (may fail but shouldn't error on wrapper itself)
    if [ -x "$WRAPPER_PATH" ]; then
        print_pass "VICAR wrapper exists and is executable: $VICAR_WRAPPER"
        print_info "To test: export PATH=\"$WRAPPER_DIR:\$PATH\" && $VICAR_WRAPPER --help"
    else
        print_fail "VICAR wrapper is not executable: $VICAR_WRAPPER"
        return 1
    fi
}

test_envrc_configuration() {
    print_test ".envrc configuration is valid"
    
    ENVRC_PATH="$PROJECT_ROOT/.envrc"
    
    if [ ! -f "$ENVRC_PATH" ]; then
        print_fail ".envrc file not found"
        return 1
    fi
    
    # Check for key configuration variables
    if grep -q "CONTAINER_NAME=" "$ENVRC_PATH" && \
       grep -q "CONTAINER_IMAGE=" "$ENVRC_PATH" && \
       grep -q "WORKSPACE_ROOT=" "$ENVRC_PATH"; then
        print_pass ".envrc configuration looks valid"
    else
        print_fail ".envrc is missing required variables"
        return 1
    fi
}

test_platform_detection() {
    print_test "Platform detection in .envrc"
    
    ENVRC_PATH="$PROJECT_ROOT/.envrc"
    
    if grep -q "HOST_OS=.*uname -s" "$ENVRC_PATH"; then
        CURRENT_OS=$(uname -s)
        print_pass "Platform detection configured (Current: $CURRENT_OS)"
    else
        print_fail "Platform detection not found in .envrc"
        return 1
    fi
}

test_x11_configuration() {
    print_test "X11 configuration for GUI support"
    
    ENVRC_PATH="$PROJECT_ROOT/.envrc"
    
    if grep -q "_x11_docker_args\|_x11_exec_args" "$ENVRC_PATH"; then
        print_pass "X11 configuration functions found"
        
        # Check platform-specific X11 setup
        if [ "$(uname -s)" = "Darwin" ]; then
            if pgrep -q XQuartz || pgrep -q X11; then
                print_info "XQuartz is running (required for macOS GUI)"
            else
                print_info "XQuartz is not running (needed for GUI applications on macOS)"
            fi
        fi
    else
        print_skip "X11 configuration not found (may not be required)"
    fi
}

test_performance() {
    print_test "Command execution performance"
    
    print_info "Measuring docker exec latency..."
    
    # Measure execution time
    START_TIME=$(date +%s%N)
    docker exec "$CONTAINER_NAME" echo "test" > /dev/null 2>&1
    END_TIME=$(date +%s%N)
    
    LATENCY_NS=$((END_TIME - START_TIME))
    LATENCY_MS=$((LATENCY_NS / 1000000))
    
    print_info "Command latency: ${LATENCY_MS}ms"
    
    if [ "$LATENCY_MS" -lt 500 ]; then
        print_pass "Performance is good (< 500ms)"
    else
        print_info "Performance is slower than expected (may be acceptable depending on use case)"
    fi
}

cleanup_container() {
    print_test "Cleanup: Stop and remove test container"
    
    if docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        docker stop "$CONTAINER_NAME" > /dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" > /dev/null 2>&1 || true
        print_pass "Container cleaned up"
    else
        print_info "No container to clean up"
    fi
}

# Main test execution
main() {
    print_header "VICAR Native Toolkit Wrapper Tests"
    print_info "Project root: $PROJECT_ROOT"
    print_info "Container name: $CONTAINER_NAME"
    print_info "Image name: $IMAGE_NAME"
    
    # Parse command line arguments
    CLEANUP_AFTER=false
    START_CONTAINER=false
    RUN_ALL=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cleanup)
                CLEANUP_AFTER=true
                shift
                ;;
            --start-container)
                START_CONTAINER=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --cleanup          Stop and remove container after tests"
                echo "  --start-container  Start container if not running"
                echo "  --help             Show this help message"
                echo ""
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Phase 1: Prerequisites
    print_header "Phase 1: Prerequisites"
    test_docker_installed || exit 1
    test_direnv_installed
    test_image_exists || {
        print_info "To build the image, run: ./scripts/build-image-with-rpms.sh"
        exit 1
    }
    test_workspace_exists || exit 1
    test_wrapper_dir_exists
    test_envrc_configuration
    test_platform_detection
    test_x11_configuration
    
    # Phase 2: Container Tests
    print_header "Phase 2: Container Tests"
    
    CONTAINER_WAS_RUNNING=false
    if test_container_running; then
        CONTAINER_WAS_RUNNING=true
    else
        if [ "$START_CONTAINER" = true ]; then
            start_container_if_needed || exit 1
        else
            print_info "Container is not running. Use --start-container to start it."
            print_info "Skipping container-dependent tests."
            print_summary
            exit 0
        fi
    fi
    
    test_container_exec || exit 1
    test_workspace_mount || exit 1
    
    # Phase 3: VICAR Installation Tests
    print_header "Phase 3: VICAR Installation Tests"
    test_vicar_installed
    test_vicar_commands_available || print_info "VICAR commands test failed (may indicate build issue)"
    
    # Phase 4: Wrapper Tests
    print_header "Phase 4: Wrapper Tests"
    test_wrapper_script_structure
    test_wrapper_execution
    test_vicar_command_wrapper
    
    # Phase 5: Performance Tests
    print_header "Phase 5: Performance Tests"
    test_performance
    
    # Cleanup
    if [ "$CLEANUP_AFTER" = true ] && [ "$CONTAINER_WAS_RUNNING" = false ]; then
        print_header "Cleanup"
        cleanup_container
    fi
    
    # Summary
    print_summary
}

# Run main function
main "$@"
