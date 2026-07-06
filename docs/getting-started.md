# Getting Started with TIG

Quick setup guide for running Mars 2020 stereo mesh generation.

## Prerequisites

- **Docker** or Podman installed
- **8GB RAM** minimum (16GB recommended)
- **M2020 stereo images** (NavCam or Mastcam-Z)

## Installation

### Option 1: Use Pre-built Image (Recommended)

```bash
docker pull ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource
```

### Option 2: Build Locally

```bash
cd terrain-intelligence-generator/docker
docker build -t terrain-intelligence-generator:opensource .
```

**Note**: Local build requires `vicario.jar` (see [Vicario Reference](../reference/vicario.md))

## Running Your First Demo

### 1. Prepare Data

Get M2020 stereo images from PDS or use sample data:

```bash
# Sample NavCam stereo pair locations:
# Left:  NLM_<SCLK>_*FDR_*.VIC
# Right: NRM_<SCLK>_*FDR_*.VIC
```

### 2. Run Mesh Generation

```bash
./demo-mesh-generation-with-xyz.sh \
  --stereo-left /path/to/left.VIC \
  --stereo-right /path/to/right.VIC
```

**Processing time**: ~10 minutes for 1280x960 images

### 3. View Results

```bash
# Check output
ls workspace/
# terrain.obj      - 3D mesh (~273M)
# terrain.mtl      - Material file
# texture.png      - Texture (1280x960)
# pointcloud.xyz   - XYZ data (~15M)

# View mesh
meshlab workspace/terrain.obj
# or
blender workspace/terrain.obj
```

## What the Demo Does

1. **Stereo Correlation** (marscorr + marscor3)
   - Matches features between left/right images
   - Generates disparity map
   - ~8 minutes

2. **XYZ Generation** (marsxyz)
   - Converts disparity to 3D coordinates
   - Filters outliers
   - ~1 minute

3. **Mesh Creation** (marsmesh)
   - Triangulates point cloud
   - Applies texture
   - ~30 seconds

4. **Format Conversion** (vicario)
   - Converts VICAR to PNG
   - <1 second

## Troubleshooting

### Container Name Conflict

```bash
docker: Error response from daemon: Conflict. The container name "/tig-mesh-demo" is already in use
```

**Solution**:
```bash
docker stop tig-mesh-demo && docker rm tig-mesh-demo
```

### Out of Memory

```bash
no additional memory available
```

**Solution**: Increase Docker memory limit to 16GB or use lower resolution images

### Missing Calibration

```bash
ERROR: MARS calibration not found
```

**Solution**: Ensure calibration files are in `terrain-intelligence-generator/docker/mars_calibration_m20/`

## Next Steps

- **[Mesh Generation Demo](demos/mesh-generation.md)** - Detailed walkthrough
- **[Command Reference](demos/commands.md)** - Available VICAR tools
- **[Vicario Reference](reference/vicario.md)** - Image format conversion

## Configuration

### Using Custom Calibration

Mount your own M2020 calibration:

```bash
docker run -v /path/to/calib:/usr/local/vicar/mars_calib:ro ...
```

### Using Pre-computed XYZ

Skip correlation if you have XYZ files:

```bash
./demo-mesh-generation-with-xyz.sh \
  --xyz pointcloud.IMG \
  --texture image.IMG
```

See [demos/mesh-generation.md](demos/mesh-generation.md) for details.
