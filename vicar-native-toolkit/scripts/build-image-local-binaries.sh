#!/bin/bash
# Build VICAR Docker image using local pre-compiled binaries
# This script builds an image from the vicar-binaries directory

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VICAR_ROOT="$(dirname "$PROJECT_ROOT")"

echo "===== VICAR Docker Image Builder (Local Binaries) ====="
echo "Project root: $PROJECT_ROOT"
echo "VICAR root: $VICAR_ROOT"
echo ""

# Check if vicar-binaries directory exists
if [ ! -d "$VICAR_ROOT/vicar-binaries" ]; then
    echo "ERROR: vicar-binaries directory not found at: $VICAR_ROOT/vicar-binaries"
    exit 1
fi

echo "✓ Found vicar-binaries directory"
echo ""

# Check if Dockerfile exists
if [ ! -f "$PROJECT_ROOT/docker/Dockerfile.local-binaries" ]; then
    echo "ERROR: Dockerfile not found: $PROJECT_ROOT/docker/Dockerfile.local-binaries"
    exit 1
fi

echo "✓ Found Dockerfile"
echo ""

echo "===== Building Docker image ====="
echo "This will take 10-15 minutes (copying large binary directory)..."
echo "Image name: vicar-tools:with-rpms"
echo "Build context: $VICAR_ROOT (includes vicar-binaries/)"
echo ""

# Build the image with build context set to VICAR_ROOT
# This allows us to COPY vicar-binaries/ in the Dockerfile
cd "$VICAR_ROOT"

docker build \
    --platform linux/amd64 \
    -f "$PROJECT_ROOT/docker/Dockerfile.local-binaries" \
    -t vicar-tools:with-rpms \
    -t vicar-tools:local-binaries \
    -t vicar-tools:latest \
    .

echo ""
echo "===== Build Complete ====="
echo ""
echo "✓ Image built successfully: vicar-tools:with-rpms"
echo ""
echo "Next steps:"
echo "  1. cd $PROJECT_ROOT"
echo "  2. direnv allow"
echo "  3. Wait for container to start"
echo "  4. Test: label --help"
echo ""
echo "The vicar-tig-demo can now use VICAR tools!"
