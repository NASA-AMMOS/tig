#!/bin/bash
# Build the TIG VICAR image from the pre-built binaries published on the
# NASA-AMMOS/VICAR GitHub releases, mirroring what CI builds.

set -e  # Exit on error

# Configuration
IMAGE_NAME="${IMAGE_NAME:-terrain-intelligence-generator}"
IMAGE_TAG="${IMAGE_TAG:-opensource}"
VICAR_VERSION="${VICAR_VERSION:-5.0}"
# Release asset names, which carry the version; the Dockerfile downloads both
# from the VICAR_VERSION release.
BINARIES_FILE="${BINARIES_FILE:-vicar_open_bin_x86-64-linx_${VICAR_VERSION}.tar.gz}"
EXTERNAL_FILE="${EXTERNAL_FILE:-vicar_open_ext_x86-64-linx_${VICAR_VERSION}.tar.gz}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}===== Building Terrain Intelligence Generator image =====${NC}"
echo ""
echo "Configuration:"
echo "  Image name: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "  VICAR version: ${VICAR_VERSION}"
echo "  Binaries tarball: ${BINARIES_FILE}"
echo "  Externals tarball: ${EXTERNAL_FILE}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="${SCRIPT_DIR}/docker"

if [ ! -f "${DOCKER_DIR}/Dockerfile" ]; then
    echo -e "${RED}ERROR: Dockerfile not found in ${DOCKER_DIR}${NC}"
    exit 1
fi

# Build the image
echo -e "${YELLOW}Building Docker image...${NC}"
echo "This will download pre-built binaries from GitHub releases and vicario from Maven Central."
echo "Estimated build time: 5-10 minutes (depending on network speed)."
echo ""

docker build \
    --platform linux/amd64 \
    -f "${DOCKER_DIR}/Dockerfile" \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    --build-arg VICAR_VERSION="${VICAR_VERSION}" \
    --build-arg BINARIES_FILE="${BINARIES_FILE}" \
    --build-arg EXTERNAL_FILE="${EXTERNAL_FILE}" \
    "${DOCKER_DIR}"

echo ""
echo -e "${GREEN}✓ Build completed successfully!${NC}"
echo ""
echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "To test it:"
echo "  ./test-docker-image.sh ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "To use it with tig:"
echo "  CONTAINER_IMAGE=${IMAGE_NAME}:${IMAGE_TAG} tig gen test.vic 64 64"
echo ""
