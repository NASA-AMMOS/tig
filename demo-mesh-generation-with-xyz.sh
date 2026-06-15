#!/bin/bash
set -e

echo "=== Terrain Intelligence Generator - Mesh Generation Demo with XYZ Calculation ==="
echo ""

# Configuration
IMAGE="ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource"
CONTAINER="tig-mesh-demo"
WORKSPACE="$(pwd)/workspace"

# Find calibration files using helper script
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
    # Fallback to default location if helper not found
    CALIB_DIR="$(pwd)/terrain-intelligence-generator/docker/mars_calibration_m20"
fi

# Parse arguments
STEREO_LEFT=""
STEREO_RIGHT=""
XYZ_FILE=""
TEXTURE_FILE=""

print_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --xyz FILE           Use pre-computed XYZ point cloud (fast)"
  echo "  --stereo-left FILE   Left stereo image (for XYZ calculation)"
  echo "  --stereo-right FILE  Right stereo image (for XYZ calculation)"
  echo "  --texture FILE       Texture image (optional, defaults to left stereo)"
  echo ""
  echo "Examples:"
  echo "  # Use pre-computed XYZ (fast, ~90 seconds)"
  echo "  $0 --xyz pointcloud.IMG --texture image.IMG"
  echo ""
  echo "  # Calculate XYZ from stereo pair (slow, ~10+ minutes)"
  echo "  $0 --stereo-left left.VIC --stereo-right right.VIC"
  echo ""
  echo "Requirements:"
  echo "  - Stereo images must be from same acquisition (matching SCLK)"
  echo "  - Full-resolution or subframe images supported"
  echo "  - Downsampled/thumbnails not recommended (causes pixel distortion)"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --xyz)
      XYZ_FILE="$2"
      shift 2
      ;;
    --stereo-left)
      STEREO_LEFT="$2"
      shift 2
      ;;
    --stereo-right)
      STEREO_RIGHT="$2"
      shift 2
      ;;
    --texture)
      TEXTURE_FILE="$2"
      shift 2
      ;;
    --help|-h)
      print_usage
      ;;
    *)
      echo "ERROR: Unknown option: $1"
      print_usage
      ;;
  esac
done

# Validate inputs
if [ -z "$XYZ_FILE" ] && [ -z "$STEREO_LEFT" ]; then
  echo "ERROR: Must specify either --xyz or --stereo-left/--stereo-right"
  print_usage
fi

if [ -n "$STEREO_LEFT" ] && [ -z "$STEREO_RIGHT" ]; then
  echo "ERROR: --stereo-right required when using --stereo-left"
  exit 1
fi

if [ -n "$STEREO_RIGHT" ] && [ -z "$STEREO_LEFT" ]; then
  echo "ERROR: --stereo-left required when using --stereo-right"
  exit 1
fi

# Verify calibration exists
echo "Using calibration from: $CALIB_DIR"
if [ ! -d "$CALIB_DIR" ]; then
  echo "ERROR: Calibration directory not accessible"
  exit 1
fi

# Create workspace
mkdir -p "$WORKSPACE"
echo "✓ Created workspace: $WORKSPACE"

# Start container with calibration mounted
echo "Starting TIG container with M2020 calibration..."
docker run -d --name "$CONTAINER" \
  -v "$WORKSPACE:/workspace:Z" \
  -v "$CALIB_DIR:/usr/local/vicar/mars_calib:ro,Z" \
  "$IMAGE" \
  tail -f /dev/null

echo "✓ Container started: $CONTAINER"
echo ""

# Step 1: Get or generate XYZ
if [ -n "$XYZ_FILE" ]; then
  # Use pre-computed XYZ
  echo "Step 1: Using pre-computed XYZ point cloud..."
  if [ ! -f "$XYZ_FILE" ]; then
    echo "ERROR: XYZ file not found: $XYZ_FILE"
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
    exit 1
  fi
  
  # Copy via docker exec to handle permissions
  XYZ_BASENAME=$(basename "$XYZ_FILE")
  docker cp "$XYZ_FILE" "$CONTAINER:/workspace/pointcloud.xyz"
  echo "✓ XYZ copied: $(du -h $XYZ_FILE | cut -f1)"
  
  # Set texture
  if [ -n "$TEXTURE_FILE" ]; then
    docker cp "$TEXTURE_FILE" "$CONTAINER:/workspace/texture.img"
  elif [ -n "$STEREO_LEFT" ]; then
    docker cp "$STEREO_LEFT" "$CONTAINER:/workspace/texture.img"
  else
    echo "ERROR: No texture specified"
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
    exit 1
  fi
else
  # Calculate XYZ from stereo pair
  echo "Step 1: Calculating XYZ from stereo pair..."
  echo "  WARNING: This takes 10+ minutes for full-resolution images"
  echo ""
  
  # Validate files exist
  if [ ! -f "$STEREO_LEFT" ]; then
    echo "ERROR: Left stereo file not found: $STEREO_LEFT"
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
    exit 1
  fi
  if [ ! -f "$STEREO_RIGHT" ]; then
    echo "ERROR: Right stereo file not found: $STEREO_RIGHT"
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
    exit 1
  fi
  
  # Copy stereo pair to workspace
  docker cp "$STEREO_LEFT" "$CONTAINER:/workspace/left.vic"
  docker cp "$STEREO_RIGHT" "$CONTAINER:/workspace/right.vic"
  echo "  ✓ Stereo pair copied"
  
  # Validate image resolution
  echo "  Checking image resolution..."
  docker exec "$CONTAINER" bash -c '
    cd /workspace
    left_nl=$(head -c 2000 left.vic | grep -a "NL=" | head -1 | sed "s/.*NL=\([0-9]*\).*/\1/")
    left_ns=$(head -c 2000 left.vic | grep -a "NS=" | head -1 | sed "s/.*NS=\([0-9]*\).*/\1/")
    echo "  Left image: ${left_ns}x${left_nl}"
    
    # Check if this is a subframe by looking for FIRST_LINE or if dimensions dont match sensor
    has_subframe=$(head -c 20000 left.vic | grep -ac "FIRST_LINE=")
    
    if [ "$has_subframe" -gt 0 ]; then
      echo "  ✓ Subframe/windowed image detected (partial sensor readout)"
      echo "  Note: Subframes are valid for stereo correlation"
    elif [ "$left_ns" -ge 3840 ] && [ "$left_nl" -ge 2880 ]; then
      echo "  ✓ Full or near-full resolution image"
    elif [ "$left_ns" -lt 500 ] || [ "$left_nl" -lt 500 ]; then
      echo "  ERROR: Images too small (${left_ns}x${left_nl})"
      echo "  Minimum ~500x500 pixels required for stereo correlation"
      exit 1
    else
      echo "  ✓ Image dimensions: ${left_ns}x${left_nl}"
      echo "  Note: Smaller subframes may have reduced mesh quality"
    fi
  '
  
  if [ $? -ne 0 ]; then
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
    exit 1
  fi
  
  # Step 1a: Stereo correlation (disparity map)
  echo ""
  echo "  Step 1a: Running stereo correlation..."
  echo "  This may take 5-15 minutes..."
  
  echo "    Running initial correlation (marscorr)..."
  docker exec "$CONTAINER" bash -c '
    cd /workspace
    export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib
    marscorr \( left.vic right.vic \) disparity_init.img template=15 search=51 quality=0.2
  ' 2>&1 | grep -E "tiepoints gathered|Seed point" | tail -3
  
  if ! docker exec "$CONTAINER" test -f /workspace/disparity_init.img; then
    echo "  ❌ ERROR: marscorr failed to generate disparity_init.img"
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
    exit 1
  fi
  echo "    ✓ Initial disparity generated"
  
  echo "    Running refinement (marscor3)..."
  docker exec "$CONTAINER" bash -c '
    cd /workspace
    export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib
    marscor3 \( left.vic right.vic \) disparity.img in_disp=disparity_init.img template=11 search=31 quality=0.4 -omp_on
  ' 2>&1 | grep -E "tiepoints|Pyramid|Zooming" | tail -3
  
  if ! docker exec "$CONTAINER" test -f /workspace/disparity.img; then
    echo "  ❌ ERROR: marscor3 failed to generate disparity.img"
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
    exit 1
  fi
  
  echo "  ✓ Disparity map generated"
  
  # Step 1b: Generate XYZ from disparity
  echo ""
  echo "  Step 1b: Generating XYZ point cloud (marsxyz)..."
  echo "  This may take 2-5 minutes..."
  docker exec "$CONTAINER" bash -c '
    cd /workspace
    export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib
    marsxyz \( left.vic right.vic \) pointcloud.xyz disp=disparity.img \
      error=10.0 abserr=0.15 lined=100 avgline=50 zlimit=\(-300,300\) spike_range=0.04 outlier=0.5
  ' 2>&1 | grep -E "Successfully|valid|rejected|XYZ" | tail -10
  
  if ! docker exec "$CONTAINER" test -f /workspace/pointcloud.xyz; then
    echo "  ❌ ERROR: marsxyz failed to generate pointcloud.xyz"
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
    exit 1
  fi
  
  echo "  ✓ XYZ point cloud generated"
  
  # Step 1c: Filter rover hardware from XYZ
  echo ""
  echo "  Step 1c: Filtering rover hardware (marsrfilt)..."
  echo "  This removes rover body, wheels, mast from point cloud..."
  docker exec "$CONTAINER" bash -c '
    cd /workspace
    export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib
    marsrfilt inp=pointcloud.xyz out=pointcloud_filtered.xyz
  ' 2>&1 | grep -E "MARSRFILT|Version|Filtering|points|removed" || true
  
  if ! docker exec "$CONTAINER" test -f /workspace/pointcloud_filtered.xyz; then
    echo "  ⚠ WARNING: marsrfilt failed, using unfiltered XYZ"
    docker exec "$CONTAINER" bash -c 'cd /workspace && cp pointcloud.xyz pointcloud_filtered.xyz'
  else
    echo "  ✓ Rover hardware filtered"
  fi
  
  # Use right image as texture (matches reference mesh workflow)
  if [ -n "$TEXTURE_FILE" ]; then
    docker cp "$TEXTURE_FILE" "$CONTAINER:/workspace/texture.img"
  else
    docker cp "$STEREO_RIGHT" "$CONTAINER:/workspace/texture.img"
  fi
fi

echo ""
echo "Step 2: Generating 3D mesh..."
echo "  This takes ~30-90 seconds..."
echo "  Note: Using adaptive decimation with filtered XYZ to match M20 IDS pipeline"
docker exec "$CONTAINER" bash -c '
  cd /workspace
  export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib
  marsmesh inp=pointcloud_filtered.xyz out=terrain.obj in_skin=texture.img \
    x_subsample=1 y_subsample=1 \
    range_min=0.2 range_mid=100 range_max=100 \
    lod_levels=10 max_angle=87.5 \
    res_min=3000 res_max=500000 density=1 -adaptive \
    maxgap=5
' 2>&1 | grep -E "MARSMESH|Version|mesh|triangles|vertices|Writing|LOD|decimat" || true

if ! docker exec "$CONTAINER" test -f /workspace/terrain.obj; then
  echo "❌ ERROR: marsmesh failed to generate terrain.obj"
  docker stop "$CONTAINER" && docker rm "$CONTAINER"
  exit 1
fi

echo "✓ Mesh generated: terrain.obj"
echo ""

# Convert texture using Java vicario
# Note: This container uses the Java implementation of vicario (vicario.jar)
# which provides proper dynamic range rescaling for 16-bit VICAR images.
# The wrapper script automatically applies: oform=byte rescale=true
echo "Step 3: Converting texture to PNG..."
docker exec "$CONTAINER" bash -c '
  cd /workspace
  vicario texture.img texture.png
'
echo "✓ Texture converted: texture.png"
echo ""

# List results
echo "Step 4: Results summary"
docker exec "$CONTAINER" bash -c 'cd /workspace && ls -lh pointcloud.xyz pointcloud_filtered.xyz terrain.obj terrain.mtl texture.png 2>/dev/null'
echo ""

echo "=== Demo Complete ==="
echo ""
echo "Generated files in: $WORKSPACE"
echo "  - pointcloud.xyz         : Raw 3D point cloud"
echo "  - pointcloud_filtered.xyz: Filtered point cloud (rover hardware removed)"
echo "  - terrain.obj            : 3D mesh (Wavefront OBJ)"
echo "  - terrain.mtl            : Material file"
echo "  - texture.png            : Texture image"
echo ""
echo "To view the mesh:"
echo "  - Blender: File → Import → Wavefront (.obj)"
echo "  - MeshLab: File → Import Mesh → terrain.obj"
echo "  - CloudCompare: File → Open → terrain.obj"
echo "  - Online: Upload to https://3dviewer.net/"
echo ""
echo "To clean up:"
echo "  docker stop $CONTAINER && docker rm $CONTAINER"
