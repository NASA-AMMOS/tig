#!/bin/bash
# VICAR Native Toolkit Bootstrap Script
# Automates setup of Docker/OCI container environment for VICAR

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ===== Configuration =====
DEFAULT_IMAGE="ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource"
DEFAULT_CONTAINER="vicar-sidecar"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
}

# ===== Usage =====
print_usage() {
    cat << EOF
VICAR Native Toolkit Bootstrap

Automates setup of the VICAR Docker/OCI environment. This script:
  - Checks prerequisites (Docker, direnv)
  - Pulls the VICAR container image
  - Creates configuration files
  - Activates the toolkit environment

Usage: $0 [OPTIONS]

Options:
  --image IMAGE        Container image to use
                       Default: ${DEFAULT_IMAGE}
  
  --container NAME     Container name to create
                       Default: ${DEFAULT_CONTAINER}
  
  --mars-calib PATH    Path to MARS calibration files (optional)
                       Will be mounted at /usr/local/vicar/mars_calib
  
  --config-only        Create config without pulling image
  
  --help, -h           Show this help message

Examples:
  # Use opensource image (default)
  $0
  
  # Use custom image
  $0 --image myregistry/vicar:custom
  
  # Include MARS calibration
  $0 --mars-calib /path/to/mars_calibration_m20
  
  # Only create config (don't pull image)
  $0 --config-only

Configuration:
  Settings can be customized by creating .envrc.local with:
    CONTAINER_IMAGE="your-image"
    CONTAINER_NAME="your-container"
    MARS_CONFIG_PATH="/path/to/calibration"

EOF
    exit 0
}

# ===== Parse Arguments =====
CONTAINER_IMAGE="${DEFAULT_IMAGE}"
CONTAINER_NAME="${DEFAULT_CONTAINER}"
MARS_CONFIG_PATH=""
CONFIG_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --image)
            CONTAINER_IMAGE="$2"
            shift 2
            ;;
        --container)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --mars-calib)
            MARS_CONFIG_PATH="$2"
            shift 2
            ;;
        --config-only)
            CONFIG_ONLY=true
            shift
            ;;
        --help|-h)
            print_usage
            ;;
        *)
            log_error "Unknown option: $1"
            echo ""
            print_usage
            ;;
    esac
done

# ===== Prerequisites Check =====
echo "=== VICAR Native Toolkit Bootstrap ==="
echo ""
echo "Checking prerequisites..."
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker not found"
    echo ""
    echo "Install Docker:"
    echo "  Ubuntu/Debian: sudo apt install docker.io"
    echo "  macOS:         brew install docker"
    echo "  Fedora:        sudo dnf install docker"
    echo ""
    echo "See: https://docs.docker.com/get-docker/"
    exit 1
fi
log_info "Docker installed"

# Check direnv
if ! command -v direnv &> /dev/null; then
    log_error "direnv not found"
    echo ""
    echo "Install direnv:"
    echo "  Ubuntu/Debian: sudo apt install direnv"
    echo "  macOS:         brew install direnv"
    echo "  Fedora:        sudo dnf install direnv"
    echo ""
    echo "Then add to shell rc (~/.bashrc or ~/.zshrc):"
    echo "  eval \"\$(direnv hook bash)\"  # for bash"
    echo "  eval \"\$(direnv hook zsh)\"   # for zsh"
    echo ""
    echo "See: https://direnv.net/docs/installation.html"
    exit 1
fi
log_info "direnv installed"

# Check Docker daemon
if ! docker info &> /dev/null; then
    log_error "Docker daemon not running"
    echo ""
    echo "Start Docker daemon:"
    echo "  Ubuntu/Debian: sudo systemctl start docker"
    echo "  macOS:         Start Docker Desktop"
    echo "  Fedora:        sudo systemctl start docker"
    exit 1
fi
log_info "Docker daemon running"

echo ""

# ===== Configuration =====
echo "Configuration:"
echo "  Image:     ${CONTAINER_IMAGE}"
echo "  Container: ${CONTAINER_NAME}"
if [[ -n "${MARS_CONFIG_PATH}" ]]; then
    echo "  MARS Calib: ${MARS_CONFIG_PATH}"
fi
echo ""

# ===== Pull Image =====
if [[ "${CONFIG_ONLY}" == "false" ]]; then
    echo "Pulling container image..."
    if docker pull "${CONTAINER_IMAGE}"; then
        log_info "Image pulled successfully"
    else
        log_error "Failed to pull image"
        echo ""
        echo "If using a custom image, ensure:"
        echo "  - Image name is correct"
        echo "  - You have pull access (docker login)"
        echo "  - Image exists in registry"
        exit 1
    fi
    echo ""
fi

# ===== Create Configuration =====
echo "Creating configuration..."

CONFIG_FILE="${SCRIPT_DIR}/.envrc.local"

if [[ -f "${CONFIG_FILE}" ]]; then
    log_warn "Configuration already exists: ${CONFIG_FILE}"
    echo "    Backing up to ${CONFIG_FILE}.backup"
    cp "${CONFIG_FILE}" "${CONFIG_FILE}.backup"
fi

cat > "${CONFIG_FILE}" << EOF
# VICAR Native Toolkit Configuration
# Generated by bootstrap.sh on $(date)

# Container settings
CONTAINER_NAME="${CONTAINER_NAME}"
CONTAINER_IMAGE="${CONTAINER_IMAGE}"

EOF

# Add MARS calibration if specified
if [[ -n "${MARS_CONFIG_PATH}" ]]; then
    # Convert to absolute path
    MARS_CONFIG_PATH="$(cd "${MARS_CONFIG_PATH}" && pwd)"
    
    if [[ ! -d "${MARS_CONFIG_PATH}" ]]; then
        log_warn "MARS calibration path does not exist: ${MARS_CONFIG_PATH}"
    else
        echo "# MARS calibration files" >> "${CONFIG_FILE}"
        echo "MARS_CONFIG_PATH=\"${MARS_CONFIG_PATH}\"" >> "${CONFIG_FILE}"
        log_info "MARS calibration configured"
    fi
fi

log_info "Configuration created: ${CONFIG_FILE}"
echo ""

# ===== Workspace Setup =====
WORKSPACE="${SCRIPT_DIR}/workspace"
if [[ ! -d "${WORKSPACE}" ]]; then
    mkdir -p "${WORKSPACE}"
    log_info "Created workspace: ${WORKSPACE}"
else
    log_info "Workspace exists: ${WORKSPACE}"
fi
echo ""

# ===== direnv Setup =====
echo "Setting up direnv..."

# Check .envrc exists
if [[ ! -f "${SCRIPT_DIR}/.envrc" ]]; then
    log_error ".envrc not found in ${SCRIPT_DIR}"
    exit 1
fi

# Allow direnv
direnv allow "${SCRIPT_DIR}"

log_info "direnv configured"
echo ""

# ===== Success =====
echo "=== Bootstrap Complete ==="
echo ""
log_info "VICAR Native Toolkit is ready!"
echo ""
echo "Next steps:"
echo "  1. Enter toolkit directory:"
echo "       cd ${SCRIPT_DIR}"
echo ""
echo "  2. Toolkit will activate automatically (via direnv)"
echo "     Or manually: source .envrc"
echo ""
echo "  3. Try commands:"
echo "       gen out=test.img nl=10 ns=10"
echo "       toolkit-status"
echo ""
if [[ -n "${MARS_CONFIG_PATH}" ]]; then
    echo "  4. Verify MARS calibration:"
    echo "       toolkit-verify-calib"
    echo ""
fi
echo "Configuration: ${CONFIG_FILE}"
echo ""
