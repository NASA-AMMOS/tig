# Mesh Generation Demos

Mars 2020 NavCam stereo terrain reconstruction using VICAR MARS tools.

## Overview

Two demos are available for generating 3D terrain meshes from Mars 2020 NavCam stereo images:

1. **Full Pipeline** (`demo-mesh-generation-with-xyz.sh`) - Complete stereo correlation → XYZ → mesh
2. **Quick Demo** (`demo-mesh-generation-complete.sh`) - Fast mesh generation from pre-computed XYZ

## Demo 1: Full Pipeline with XYZ Calculation

Complete stereo mesh generation pipeline from raw stereo pair.

### What It Does

1. **Stereo Correlation** (marscorr + marscor3) - Generate disparity maps (~8 minutes)
2. **XYZ Generation** (marsxyz) - Convert disparity to 3D coordinates (~1 minute)
3. **Mesh Creation** (marsmesh) - Triangulate surface (~30 seconds)
4. **Texture Conversion** (vicario) - VICAR to PNG (<1 second)

**Total Time:** ~10 minutes for 1280x960 NavCam images

### Prerequisites

- Docker Engine 20.10+
- M2020 NavCam stereo pair (FDR format)
- 16GB RAM recommended
- M2020 calibration files (included in Docker image)

### Usage

```bash
# Run with your stereo pair
./demo-mesh-generation-with-xyz.sh \
  --stereo-left /path/to/NLM_*_FDR_*.VIC \
  --stereo-right /path/to/NRM_*_FDR_*.VIC
```

**Output** (in `workspace/`):
- `terrain.obj` - 3D mesh (~273M, 1.2M vertices)
- `terrain.mtl` - Material file
- `texture.png` - Texture image (1280x960)
- `pointcloud.xyz` - XYZ point cloud (~15M)
- `disparity.img` - Disparity map
- `terrain.iv` - OpenInventor format

### Example

```bash
# With M2020 NavCam data
./demo-mesh-generation-with-xyz.sh \
  --stereo-left NLM_1835_0829848458_777FDR_N0874924NCAM00230_0A02LLJ01.VIC \
  --stereo-right NRM_1835_0829848458_777FDR_N0874924NCAM00230_0A02LLJ01.VIC
```

### Algorithm Parameters

**Stereo Correlation:**
- Initial (marscorr): `template=15 search=51 quality=0.2`
- Refinement (marscor3): `template=11 search=31 quality=0.4 -omp_on`

**XYZ Generation:**
- Filters: `error=10.0 abserr=0.15 spike_range=0.04 outlier=0.5`
- Coordinate frame: SITE_FRAME

**Mesh Generation:**
- Subsampling: `x_subsample=2 y_subsample=2`
- Gap filling: `maxgap=5`

## Demo 2: Quick Mesh from Pre-computed XYZ

Fast demo using pre-computed XYZ point cloud from VISOR sample data.

### What It Does

1. **Copy XYZ** - Load pre-computed point cloud from VISOR
2. **Mesh Creation** (marsmesh) - Triangulate surface (~30 seconds)
3. **Texture Conversion** (vicario) - VICAR to PNG (<1 second)

**Total Time:** ~90 seconds

### Usage

```bash
# Run with defaults (uses VISOR sample data)
./demo-mesh-generation-complete.sh
```

**Output** (in `workspace/`):
- `terrain.obj` - 3D mesh (~179M, 752K vertices)
- `terrain.mtl` - Material file
- `texture.png` - Texture image (1280x960)
- `pointcloud.xyz` - XYZ point cloud (~13M)
- `terrain.iv` - OpenInventor format

### Data Source

Uses pre-computed NavCam XYZ from VISOR samples:
- **XYZ**: `NLB_712299404XYZ_F0961766NCAM00353M1.IMG`
- **Texture**: `NLB_712299404EDR_F0961766NCAM00353M1.IMG`
- **Mission**: Mars 2020 Perseverance
- **Camera**: NavCam Left

## Viewing Results

### MeshLab

```bash
meshlab workspace/terrain.obj
```

**Note**: High-resolution meshes (>1M vertices) may exceed MeshLab memory limits.

### Blender

```bash
blender workspace/terrain.obj
```

Or: File → Import → Wavefront (.obj)

### CloudCompare

```bash
CloudCompare workspace/terrain.obj
```

### Online Viewer

Upload to https://3dviewer.net/ for browser-based viewing.

## Input Requirements

### M2020 NavCam Stereo Pair

**Naming Pattern:**
- Left: `NL[M|B]_<SCLK>_*FDR_*.VIC`
- Right: `NR[M|B]_<SCLK>_*FDR_*.VIC`

**Format:**
- VICAR format
- 16-bit grayscale (HALFWORD)
- Typical sizes: 1280x960 (4x downsampled) or 5120x3840 (full-res)

**Requirements:**
- Same SCLK (spacecraft clock) timestamp
- Same sequence ID (NCAM)
- Radiometrically calibrated (FDR product type)

### Where to Get M2020 Data

**PDS Imaging Node:**
- https://pds-imaging.jpl.nasa.gov/
- Search by Sol, SCLK, or instrument
- Filter: Product Type = FDR
- Download stereo pairs with matching SCLK

## Troubleshooting

### Container Already Exists

```bash
docker stop tig-mesh-demo && docker rm tig-mesh-demo
```

### Out of Memory

Reduce mesh resolution by adjusting `x_subsample` and `y_subsample` parameters in the script.

### Correlation Fails

Ensure:
- Images are from same acquisition (matching SCLK)
- Both images are same resolution
- Calibration files present in `terrain-intelligence-generator/docker/mars_calibration_m20/`

### Wrong Camera Model

Verify image labels:
```bash
docker exec tig-mesh-demo label workspace/left.vic | grep INSTRUMENT_ID
# Should show: NAVCAM_LEFT or NAVCAM_RIGHT
```

## Clean Up

```bash
# Stop and remove container
docker stop tig-mesh-demo && docker rm tig-mesh-demo

# Remove workspace
rm -rf workspace/
```

## Advanced: Custom Parameters

Edit demo scripts to adjust:
- Correlation quality thresholds
- XYZ filtering parameters
- Mesh subsampling rates
- Texture source (left vs right camera)

See [Command Reference](commands.md) for tool parameter details.

## Performance

### 1280x960 Images (4x downsampled)

| Stage | Time | Output |
|-------|------|--------|
| marscorr | ~6 min | 1.1M tiepoints |
| marscor3 | ~2 min | 1.1M refined (87% coverage) |
| marsxyz | ~1 min | 926K XYZ points |
| marsmesh | ~30 sec | 1.2M vertices, 2.3M faces |
| vicario | <1 sec | 1280x960 PNG |
| **Total** | **~10 min** | **273M OBJ** |

### Memory Usage

- **Minimum**: 8GB RAM
- **Recommended**: 16GB RAM
- **High-res (5120x3840)**: 32GB+ RAM

## See Also

- [Getting Started](../getting-started.md) - Initial setup
- [Command Reference](commands.md) - VICAR tool details
- [Architecture](../architecture/components.md) - System overview
