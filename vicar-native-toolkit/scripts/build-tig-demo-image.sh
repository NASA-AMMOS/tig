#!/bin/bash
# Build VICAR TIG Demo Docker image with Python dependencies
# This extends vicar-tools:with-rpms with Python packages needed for the demo

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "===== VICAR TIG Demo Image Builder ====="
echo "Project root: $PROJECT_ROOT"
echo ""

# Check if base image exists
echo "===== Checking for base image ====="
if ! docker image inspect vicar-tools:with-rpms &> /dev/null; then
    echo "❌ ERROR: Base image 'vicar-tools:with-rpms' not found"
    echo ""
    echo "   You need to build the base image first:"
    echo "     cd $PROJECT_ROOT"
    echo "     ./scripts/build-image-with-rpms.sh"
    echo ""
    exit 1
fi

echo "✓ Base image 'vicar-tools:with-rpms' found"
echo ""

# Check if Dockerfile exists
if [ ! -f "$PROJECT_ROOT/docker/Dockerfile.tig-demo" ]; then
    echo "ERROR: Dockerfile not found: $PROJECT_ROOT/docker/Dockerfile.tig-demo"
    exit 1
fi

echo "✓ Dockerfile found"
echo ""

echo "===== Building Docker image ====="
echo "Base image: vicar-tools:with-rpms"
echo "New image: vicar-tools:tig-demo"
echo ""
echo "This will install Python dependencies:"
echo "  - numpy >= 1.20.0"
echo "  - scipy >= 1.7.0"
echo "  - Pillow >= 9.0.0"
echo "  - PyYAML >= 5.4.0"
echo "  - click >= 8.0.0"
echo "  - matplotlib >= 3.3.0"
echo ""
echo "This should take 2-3 minutes..."
echo ""

# RHEL/Oracle Linux base requires linux/amd64 (no ARM64 support for Oracle Linux 8.9)
DOCKER_PLATFORM="linux/amd64"
PLATFORM=$(uname -m)

if [ "$PLATFORM" = "arm64" ] || [ "$PLATFORM" = "aarch64" ]; then
    echo "NOTE: Building for linux/amd64 on ARM64 host (Apple Silicon)"
    echo "Image will run under emulation"
    echo ""
fi

echo "Building for platform: $DOCKER_PLATFORM"
echo ""

# Build the image
docker build \
    --platform "$DOCKER_PLATFORM" \
    --file "$PROJECT_ROOT/docker/Dockerfile.tig-demo" \
    --tag vicar-tools:tig-demo \
    --progress=plain \
    "$PROJECT_ROOT/docker"

BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "===== Build successful! ====="
    echo ""
    echo "Image created: vicar-tools:tig-demo"
    echo ""
    echo "Next steps:"
    echo ""
    echo "  1. Test Python dependencies:"
    echo "     docker run --rm vicar-tools:tig-demo python3 -c 'import numpy, scipy, PIL, yaml, click; print(\"All dependencies available\")'"
    echo ""
    echo "  2. Run TIG demo Stage 1 (EDR Processing):"
    echo "     docker run --rm \\"
    echo "       -v /path/to/vicar-tig-demo:/tig-demo \\"
    echo "       -v /path/to/project:/project \\"
    echo "       -e V2TOP=/usr/local/vicar/m20-g87 \\"
    echo "       -e VICAR_PARAM=/project/calibration/param_files \\"
    echo "       -e VICAR_CALIB=/project/calibration \\"
    echo "       -e R2LIB=/usr/local/vicar/m20-g87 \\"
    echo "       --workdir /tig-demo \\"
    echo "       vicar-tools:tig-demo \\"
    echo "       python3 scripts/01-process-edr.py --left data/input/m20_left.vic --right data/input/m20_right.vic --output data/cache/calibrated/ -v"
    echo ""
    echo "  3. Run TIG demo Stage 3 (Mesh Generation):"
    echo "     docker run --rm \\"
    echo "       -v /path/to/vicar-tig-demo:/tig-demo \\"
    echo "       -v /path/to/project:/project \\"
    echo "       -e V2TOP=/usr/local/vicar/m20-g87 \\"
    echo "       --workdir /tig-demo \\"
    echo "       vicar-tools:tig-demo \\"
    echo "       python3 scripts/03-generate-mesh.py --disparity data/cache/disparity.vic --output data/output/terrain.obj -v"
    echo ""
    echo "  4. Update docker-compose.yml or scripts to use vicar-tools:tig-demo"
    echo ""
    
    # Show image size
    echo "Image size:"
    docker images vicar-tools:tig-demo --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}"
    echo ""
    
    # Show comparison with base image
    echo "Size comparison:"
    docker images --filter "reference=vicar-tools:with-rpms" --filter "reference=vicar-tools:tig-demo" --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}"
    
else
    echo ""
    echo "===== Build failed! ====="
    echo "Exit code: $BUILD_EXIT_CODE"
    echo ""
    echo "Troubleshooting:"
    echo "  - Check Docker logs above for errors"
    echo "  - Verify base image exists: docker images vicar-tools:with-rpms"
    echo "  - Check network connectivity for pip downloads"
    echo "  - Ensure Docker has sufficient memory (recommend 4GB+)"
    echo ""
    exit $BUILD_EXIT_CODE
fi
