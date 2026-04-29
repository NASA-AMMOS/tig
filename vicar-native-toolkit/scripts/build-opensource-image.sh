#!/bin/bash
# Build VICAR Native Toolkit - Open Source Edition
# This script builds the VICAR container using pre-built binaries from GitHub releases

set -e  # Exit on error

# Configuration
IMAGE_NAME="${IMAGE_NAME:-vicar-native-toolkit}"
IMAGE_TAG="${IMAGE_TAG:-opensource}"
VICAR_VERSION="${VICAR_VERSION:-5.0}"
EXTERNAL_VERSION="${EXTERNAL_VERSION:-5.0}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}===== Building VICAR Native Toolkit - Open Source Edition =====${NC}"
echo ""
echo "Configuration:"
echo "  Image name: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "  VICAR version: ${VICAR_VERSION}"
echo "  Externals version: ${EXTERNAL_VERSION}"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
DOCKER_DIR="${PROJECT_DIR}/docker"

# Check if Dockerfile exists
if [ ! -f "${DOCKER_DIR}/Dockerfile" ]; then
    echo -e "${RED}ERROR: Dockerfile not found in ${DOCKER_DIR}${NC}"
    exit 1
fi

# Check if vicario script exists
if [ ! -f "${PROJECT_DIR}/scripts/vicario" ]; then
    echo -e "${RED}ERROR: vicario script not found in ${PROJECT_DIR}/scripts${NC}"
    exit 1
fi

# Build the image
echo -e "${YELLOW}Building Docker image...${NC}"
echo "This will download pre-built binaries from GitHub releases."
echo "Estimated build time: 5-10 minutes (depending on network speed)."
echo ""

docker build \
    --platform linux/amd64 \
    -f "${DOCKER_DIR}/Dockerfile" \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    --build-arg VICAR_VERSION="${VICAR_VERSION}" \
    --build-arg EXTERNAL_VERSION="${EXTERNAL_VERSION}" \
    "${PROJECT_DIR}"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Build completed successfully!${NC}"
    echo ""
    echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    echo "To run the container:"
    echo "  docker run -it --rm ${IMAGE_NAME}:${IMAGE_TAG} bash"
    echo ""
    echo "To test VICAR commands:"
    echo "  docker run -it --rm ${IMAGE_NAME}:${IMAGE_TAG} label --help"
    echo ""
    echo "To convert VICAR images:"
    echo "  docker run -it --rm -v \$(pwd):/workspace ${IMAGE_NAME}:${IMAGE_TAG} vicario input.vic output.png"
    echo ""
else
    echo ""
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi
