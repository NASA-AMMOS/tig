# Mesh Generation Demos

Mars 2020 NavCam stereo terrain reconstruction using VICAR MARS tools.

## Overview

Three demos are available for generating 3D terrain meshes from Mars 2020 NavCam stereo images:

1. **Full Pipeline** (`demo-mesh-generation-with-xyz.sh`) - Complete stereo correlation → XYZ → mesh
2. **Quick Demo** (`demo-mesh-generation-complete.sh`) - Fast mesh generation from pre-computed XYZ
3. **Native Toolkit** (`demo-mesh-native-toolkit.sh`) - Native-looking commands via vicar-native-toolkit

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
- M2020 calibration files mounted at `./calibration/` (see [Calibration Setup](#calibration-setup))

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
- **XYZ:** `nlf_1835_0829848458_777xyz_n0874924ncam00230_0a02llj08.img`
- **Texture:** `nlm_1835_0829848458_777fdr_n0874924ncam00230_0a02llj01.vic`

VISOR (Visible Sightseeing Observables Repository) provides processed M2020 data products.

## Demo 3: Native Toolkit with vicar-native-toolkit

**NEW:** Demonstrates native-looking VICAR commands using the vicar-native-toolkit wrapper.

### What It Does

Uses `vicar-native-toolkit` to provide native-looking command execution:

```bash
# Instead of:
docker exec vicar-sidecar marsmesh inp=cloud.xyz out=mesh.obj ...

# You run:
marsmesh inp=cloud.xyz out=mesh.obj ...
```

Commands look and feel like native binaries but transparently execute inside Docker.

### Key Features

- **Native appearance:** Commands execute from any directory in workspace
- **Persistent container:** Long-running `vicar-sidecar` container (no startup overhead)
- **Auto-discovery:** All 200+ VICAR commands automatically wrapped
- **Path transparency:** Relative paths work naturally
- **direnv activation:** Toolkit auto-activates when entering directory

### Prerequisites

- Docker Engine 20.10+
- **direnv** installed and configured
- M2020 calibration files (optional, required for stereo processing)
- Shell integration: `eval "$(direnv hook bash)"` in `.bashrc`

### Setup

```bash
# 1. Install direnv
sudo apt install direnv  # Ubuntu/Debian
brew install direnv      # macOS

# 2. Add to shell profile
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
source ~/.bashrc

# 3. Trust the toolkit directory (one-time)
cd vicar-native-toolkit
direnv allow
```

### Usage

```bash
# With pre-computed XYZ (fast)
./demo-mesh-native-toolkit.sh \
  --xyz pointcloud.IMG \
  --texture image.IMG

# With stereo pair (full pipeline)
./demo-mesh-native-toolkit.sh \
  --stereo-left NLM_*.VIC \
  --stereo-right NRM_*.VIC
```

### How It Works

1. **Container startup:** `direnv` detects `.envrc` and starts `vicar-sidecar` container
2. **Wrapper generation:** Auto-discovers VICAR commands and creates wrapper scripts
3. **PATH injection:** Adds wrappers to `$PATH` transparently
4. **Command execution:** Wrappers forward to `docker exec` with proper working directory

Example wrapper (`~/.direnv/wrappers/marsmesh`):
```bash
#!/bin/bash
TOOL_NAME="marsmesh"
CONTAINER_NAME="vicar-sidecar"
WORKSPACE_ROOT="/path/to/workspace"
REL_PATH="$(realpath --relative-to="${WORKSPACE_ROOT}" "${PWD}")"
docker exec -i -w "/workspace/${REL_PATH}" "${CONTAINER_NAME}" "${TOOL_NAME}" "$@"
```

### Toolkit Commands

Once activated, you have access to:

**Core VICAR:**
- `gen` - Generate test images
- `label` - Display VICAR metadata
- `list` - List image contents
- `vicario` - VICAR to PNG/JPEG converter

**MARS Terrain Tools:**
- `marscorr`, `marscor3` - Stereo correlation
- `marsxyz` - Disparity to XYZ conversion
- `marsrfilt` - Rover hardware filtering
- `marsmesh` - Mesh generation
- `marsmap` - Orthoprojection
- `marsmos` - Mosaicking

**Utility Commands:**
- `toolkit-status` - Show container status
- `toolkit-shell` - Open bash shell in container
- `toolkit-verify-calib` - Check MARS calibration
- `toolkit-stop` - Stop and remove container
- `toolkit-restart` - Restart container

### Output

Same as Demo 1, but generated in `vicar-native-toolkit/workspace/`:
- `terrain.obj` - 3D mesh
- `terrain.mtl` - Material file
- `texture.png` - Texture image
- `pointcloud.xyz` - XYZ point cloud
- `pointcloud_filtered.xyz` - Filtered (rover hardware removed)

### Advantages

**vs. Docker Exec Scripts:**
- ✓ Clean syntax: `marsmesh ...` not `docker exec container bash -c '...'`
- ✓ Persistent container: No startup/cleanup overhead per command
- ✓ Natural workflows: Chain commands with pipes/redirection
- ✓ Interactive use: Better for development/experimentation

**vs. Native Installation:**
- ✓ Consistent environment: Same VICAR version for all users
- ✓ Easy updates: `docker pull` to upgrade
- ✓ No system pollution: VICAR stays containerized
- ✓ Reproducible: Docker image hash ensures identical behavior

### Container Lifecycle

**Automatic management:**
- Started on first `cd vicar-native-toolkit` (via direnv)
- Reused across sessions (persistent)
- Survives shell exit

**Manual control:**
```bash
cd vicar-native-toolkit

# Check status
toolkit-status

# Open shell in container
toolkit-shell

# Stop container
toolkit-stop

# Restart (stop + re-enter directory)
toolkit-restart
cd .. && cd -
```

### Advanced Configuration

Edit `vicar-native-toolkit/.envrc.local`:

```bash
# Custom calibration path
export MARS_CONFIG_PATH="/path/to/mars_calib"

# Custom container name
export CONTAINER_NAME="my-vicar-sidecar"

# Custom image
export CONTAINER_IMAGE="ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:v2.0"

# Mount parent directory (for accessing files outside workspace)
export PARENT_DIR="/data"
export PARENT_MOUNT="/external"
```

## Comparison Matrix

| Feature | Demo 1 (docker exec) | Demo 2 (Quick) | Demo 3 (Native Toolkit) |
|---------|---------------------|----------------|-------------------------|
| **Execution** | Temporary container | Temporary container | Persistent sidecar |
| **Syntax** | `docker exec ...` | `docker exec ...` | `marsmesh ...` |
| **Startup time** | ~5s per run | ~5s per run | ~2s first time, instant after |
| **Cleanup** | Manual | Manual | Automatic (optional) |
| **Use case** | One-off demos | Quick testing | Development, interactive use |
| **Commands** | Manual `docker exec` | Manual `docker exec` | Native-looking wrappers |
| **Path handling** | Absolute in container | Absolute in container | Transparent relative paths |
| **Prerequisites** | Docker | Docker | Docker + direnv |

## Viewing Meshes

All demos output standard Wavefront OBJ format:

**Desktop viewers:**
- **Blender:** File → Import → Wavefront (.obj) - Best for editing/rendering
- **MeshLab:** File → Import Mesh - Best for analysis/measurements
- **CloudCompare:** File → Open - Best for point cloud comparison

**Online viewers:**
- https://3dviewer.net/ - No installation required
- Drag and drop `terrain.obj` + `texture.png`

**Command-line inspection:**
```bash
# Vertex count
grep -c "^v " terrain.obj

# Triangle count
grep -c "^f " terrain.obj

# Bounding box
grep "^v " terrain.obj | awk '{print $2,$3,$4}' | \
  awk 'NR==1{min_x=max_x=$1; min_y=max_y=$2; min_z=max_z=$3}
       {if($1<min_x) min_x=$1; if($1>max_x) max_x=$1;
        if($2<min_y) min_y=$2; if($2>max_y) max_y=$2;
        if($3<min_z) min_z=$3; if($3>max_z) max_z=$3}
       END{print "X:", min_x, max_x; print "Y:", min_y, max_y; print "Z:", min_z, max_z}'
```

## Troubleshooting

### Demo 3 (Native Toolkit) Issues

**"direnv not allowed":**
```bash
cd vicar-native-toolkit
direnv allow
```

**"Commands not found":**
```bash
# Check if container running
docker ps | grep vicar-sidecar

# Check PATH
echo $PATH | grep -o wrappers

# Re-activate
cd .. && cd vicar-native-toolkit
```

**"MARS calibration not found":**
```bash
cd vicar-native-toolkit
toolkit-verify-calib
```

**Container won't start:**
```bash
# Check logs
docker logs vicar-sidecar

# Force cleanup
docker stop vicar-sidecar && docker rm vicar-sidecar

# Re-enter directory
cd .. && cd vicar-native-toolkit
```

### General Issues

**Out of memory:**
- Increase Docker memory limit (Settings → Resources)
- Use smaller images (subframes instead of full resolution)
- Reduce `res_max` in marsmesh

**Calibration errors:**
- Verify MARS_CONFIG_PATH points to valid calibration directory
- Check calibration includes camera models for your instrument
- Use `find-calibration.sh` to locate calibration files

**Poor mesh quality:**
- Use full-resolution images (not thumbnails/downsampled)
- Adjust stereo correlation quality threshold
- Tune marsmesh decimation parameters

## Data Sources

**M2020 NavCam Images:**
- VISOR: https://mars.nasa.gov/mmgis-maps/M20/Layers/json/
- PDS Geosciences Node: https://pds-geosciences.wustl.edu/missions/mars2020/
- Look for `*_FDR_*.VIC` (Full Data Record format)

**Sample Data:**
- VISOR pre-computed XYZ products: `*_xyz_*.img`
- Included in TIG repository: `workspace/samples/`

## References

- [VICAR Documentation](https://github.com/NASA-AMMOS/VICAR)
- [MARS Tools Overview](../architecture/components.md)
- [vicar-native-toolkit README](../../vicar-native-toolkit/README.md)
- [Docker Best Practices](../development/docker.md)
