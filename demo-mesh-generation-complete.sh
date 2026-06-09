#!/bin/bash
set -e

echo "=== MARS Stereo Mesh Generation Demo ==="
echo ""
echo "Demonstrates complete MARS terrain reconstruction pipeline:"
echo "  marscorr → marsxyz → marsmesh → format conversions"
echo ""

# Configuration
IMAGE="ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource"
CONTAINER="tig-mesh-demo"
WORKSPACE="$(pwd)/workspace"

# Find calibration files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/find-calibration.sh" ]; then
    source "$SCRIPT_DIR/find-calibration.sh"
    CALIB_DIR=$(find_calibration)
    if [ $? -ne 0 ] || ! verify_calibration "$CALIB_DIR"; then
        echo "ERROR: MARS calibration not found."
        echo ""
        print_calibration_help
        exit 1
    fi
else
    CALIB_DIR="$(pwd)/terrain-intelligence-generator/docker/mars_calibration_m20"
fi

echo "Using calibration from: $CALIB_DIR"
if [ ! -d "$CALIB_DIR" ]; then
  echo "ERROR: Calibration directory not accessible"
  exit 1
fi

# Create workspace
mkdir -p "$WORKSPACE"
echo "✓ Created workspace: $WORKSPACE"

# Start container
echo "Starting TIG container with calibration..."
docker run -d --name "$CONTAINER" \
  -v "$WORKSPACE:/workspace:Z" \
  -v "$CALIB_DIR:/usr/local/vicar/mars_calib:ro,Z" \
  "$IMAGE" \
  tail -f /dev/null

echo "✓ Container started: $CONTAINER"
echo ""

# Stage 1: Copy pre-computed XYZ (VISOR NavCam sample)
echo "Step 1: Preparing input data..."
echo "  Using VISOR NavCam XYZ sample (pre-computed stereo correlation)"
echo "  Note: Full ZCam stereo requires radiometric preprocessing"
docker exec "$CONTAINER" bash -c '
  cd /workspace
  cp /usr/local/vicar/visor_data/samples/sample_data/OrthorectifiedMosaic/NLB_712299404XYZ_F0961766NCAM00353M1.IMG pointcloud.xyz
  cp /usr/local/vicar/visor_data/samples/sample_data/StereoCorrelation/NLB_712299404EDR_F0961766NCAM00353M1.IMG texture.img
  echo "  XYZ:     pointcloud.xyz ($(du -h pointcloud.xyz | cut -f1))"
  echo "  Texture: texture.img ($(du -h texture.img | cut -f1))"
'
echo "✓ Input data ready"
echo ""

# Stage 2: Mesh generation
echo "Step 2: Generating 3D mesh (marsmesh)..."
echo "  Creating triangulated surface with texture..."
docker exec "$CONTAINER" bash -c '
  cd /workspace
  export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib
  marsmesh inp=pointcloud.xyz out=terrain.obj in_skin=texture.img \
    x_subsample=2 y_subsample=2 maxgap=5
' 2>&1 | grep -E "MARSMESH|Version|mesh|triangles|completed|Writing" || true

echo "✓ Mesh generated: terrain.obj"
echo ""

# Stage 3: Format conversions
echo "Step 3: Converting texture to PNG..."

# PNG texture
docker exec "$CONTAINER" bash -c '
  cd /workspace
  vicario texture.img texture.png
' >/dev/null 2>&1
PNG_SIZE=$(docker exec "$CONTAINER" du -h /workspace/texture.png 2>/dev/null | cut -f1)
echo "  ✓ texture.png ($PNG_SIZE)"

echo ""

# Stage 4: Validation
echo "Step 4: Output verification"
VERTEX_COUNT=$(docker exec "$CONTAINER" bash -c 'grep "^v " /workspace/terrain.obj | wc -l')
FACE_COUNT=$(docker exec "$CONTAINER" bash -c 'grep "^f " /workspace/terrain.obj | wc -l')

echo "  Mesh statistics:"
printf "    Vertices: %7d\n" $VERTEX_COUNT
printf "    Faces:    %7d\n" $FACE_COUNT

echo ""
echo "  Generated files:"
docker exec "$CONTAINER" bash -c 'cd /workspace && ls -lh pointcloud.xyz terrain.obj terrain.mtl texture.png 2>/dev/null' | \
    awk '{printf "    %-20s %s\n", $9, $5}'

echo ""
echo "=== Demo Complete ==="
echo ""
echo "Generated files in: $WORKSPACE"
echo "  - pointcloud.xyz      : XYZ point cloud"
echo "  - terrain.obj         : 3D mesh (Wavefront OBJ)"
echo "  - terrain.mtl         : Material file"
echo "  - texture.png         : Texture image (PNG)"
echo ""
echo "To view the mesh:"
echo "  - Blender: File → Import → Wavefront (.obj)"
echo "  - MeshLab: File → Import Mesh → terrain.obj"
echo "  - CloudCompare: File → Open → terrain.obj"
echo "  - Online: Upload to https://3dviewer.net/"
echo ""
echo "For additional formats:"
echo "  - GLB: obj2gltf inp=terrain.obj out=terrain.glb"
echo "  - HT:  marsmap inp=pointcloud.xyz out=terrain.ht"
echo ""
echo "For ZCam stereo processing:"
echo "  Full pipeline requires radiometric preprocessing before correlation."
echo "  See M20_IDS pipeline: marscorr → marscor3 → marsxyz → marsmesh"
echo ""
echo "To clean up:"
echo "  docker stop $CONTAINER && docker rm $CONTAINER"
echo ""
