# VICAR Native Toolkit Demo - Mars Terrain Mesh Generation

Generate textured 3D terrain meshes from Mars rover stereo images using **native-looking** VICAR commands.

## What This Demo Shows

- **Native-like commands**: Run `marsmesh`, `marsxyz`, `marscorr` as if installed locally
- **Transparent Docker**: Commands execute in container without Docker syntax
- **Fast execution**: Long-running container (~50-100ms latency)
- **Complete pipeline**: Stereo → Disparity → XYZ → 3D Mesh → Texture

## Prerequisites

### Required

- **Docker** - Container runtime
- **direnv** - Environment automation
- **~6GB disk space** - For Docker image

### Install direnv

```bash
# Ubuntu/Debian
sudo apt install direnv

# macOS
brew install direnv

# Fedora
sudo dnf install direnv
```

### Configure Shell

Add to `~/.bashrc` (bash) or `~/.zshrc` (zsh):

```bash
# For bash
eval "$(direnv hook bash)"

# For zsh
eval "$(direnv hook zsh)"
```

Then reload:

```bash
source ~/.bashrc  # or source ~/.zshrc
```

## Quick Start (3 Steps)

### 1. Activate Toolkit

```bash
cd vicar-native-toolkit
direnv allow
```

**What happens:**
- ✓ Starts `vicar-sidecar` container
- ✓ Generates ~550 command wrappers
- ✓ Adds VICAR commands to PATH
- ✓ Mounts workspace directory

**Time:** ~30 seconds (first time)

### 2. Verify Activation

```bash
# Check status
toolkit-status

# Test basic command
cd workspace
gen out=test.img nl=10 ns=10
```

**Expected output:**
```
Beginning VICAR task GEN
GEN Version 2019-05-28
GEN task completed
```

✅ **Success!** No Docker syntax needed.

### 3. Run Mesh Generation

Choose one:

#### Option A: Pre-computed XYZ (Fast ~90 seconds)

```bash
# From repository root
./demo-mesh-native-toolkit.sh \
  --xyz /path/to/pointcloud.xyz \
  --texture /path/to/image.IMG
```

#### Option B: Full Stereo Pipeline (Slow ~10-15 minutes)

```bash
# From repository root
./demo-mesh-native-toolkit.sh \
  --stereo-left /path/to/left.VIC \
  --stereo-right /path/to/right.VIC
```

**Requirements for stereo processing:**
- MARS calibration files (automatically detected)
- Matching stereo pair (same SCLK timestamp)

## Step-by-Step Manual Process

Want to understand each step? Run commands manually:

### Step 0: Activate and Navigate

```bash
cd vicar-native-toolkit
direnv allow
cd workspace
```

### Step 1: Process Stereo Pair

#### 1a. Copy Stereo Images

```bash
cp /path/to/left.VIC left.vic
cp /path/to/right.VIC right.vic
```

#### 1b. Generate Disparity Map (Initial)

```bash
marscorr \( left.vic right.vic \) disparity_init.img \
  template=15 search=51 quality=0.2
```

**Time:** ~3-5 minutes  
**Output:** `disparity_init.img`

#### 1c. Refine Disparity Map

```bash
marscor3 \( left.vic right.vic \) disparity.img \
  in_disp=disparity_init.img \
  template=11 search=31 quality=0.4 -omp_on
```

**Time:** ~5-10 minutes  
**Output:** `disparity.img`

### Step 2: Generate XYZ Point Cloud

```bash
marsxyz \( left.vic right.vic \) pointcloud.xyz \
  disp=disparity.img \
  error=10.0 abserr=0.15 lined=100 avgline=50 \
  zlimit=\(-300,300\) spike_range=0.04 outlier=0.5
```

**Time:** ~30-60 seconds  
**Output:** `pointcloud.xyz`

### Step 3: Filter Rover Hardware

```bash
marsrfilt inp=pointcloud.xyz out=pointcloud_filtered.xyz
```

**Time:** ~5 seconds  
**Output:** `pointcloud_filtered.xyz` (rover parts removed)

### Step 4: Generate 3D Mesh

```bash
marsmesh inp=pointcloud_filtered.xyz out=terrain.obj \
  in_skin=right.vic \
  x_subsample=1 y_subsample=1 \
  range_min=0.2 range_mid=100 range_max=100 \
  lod_levels=10 max_angle=87.5 \
  res_min=3000 res_max=500000 density=1 -adaptive \
  maxgap=5
```

**Time:** ~30 seconds  
**Output:** `terrain.obj`, `terrain.mtl`, `terrain.iv`, `terrain.lbl`

**Note:** marsmesh generates multiple output files:
- `terrain.obj` - 3D mesh in Wavefront OBJ format (~55MB)
- `terrain.mtl` - Material file referencing texture
- `terrain.iv` - Open Inventor format mesh (~47MB)
- `terrain.lbl` - PDS4 metadata label describing mesh structure

### Step 5: Convert Texture to PNG

```bash
vicario right.vic texture.png
```

**Time:** ~2 seconds  
**Output:** `texture.png`

### Step 6: View Results

```bash
ls -lh terrain.obj terrain.mtl texture.png pointcloud_filtered.xyz
```

## Understanding the Commands

### Native-Looking vs Docker Reality

**What you type:**
```bash
marsmesh inp=pointcloud.xyz out=terrain.obj
```

**What actually happens:**
```bash
docker exec -i vicar-sidecar \
  -w /workspace \
  marsmesh inp=pointcloud.xyz out=terrain.obj
```

The wrapper handles all Docker complexity transparently!

### Command Wrappers

All commands are symlinks to a universal wrapper:

```bash
# Check wrapper
which marsmesh
# → .direnv/wrappers/marsmesh

# View wrapper implementation
cat .direnv/wrappers/marsmesh
# → Symlink to vicar-exec
```

### Available Commands

```bash
# List all 550+ wrappers
ls .direnv/wrappers/ | wc -l

# Mars processing tools
ls .direnv/wrappers/ | grep ^mars
# marscorr, marscor3, marsxyz, marsmesh, marsrfilt, marsmap, marsmos, ...

# Basic VICAR tools
ls .direnv/wrappers/ | grep -E "^(gen|label|hist|copy)"
# gen, label, hist, copy, ...

# Format conversion
ls .direnv/wrappers/ | grep vicario
# vicario (Java-based image converter)
```

## Viewing Output

### 3D Mesh Viewers

**Blender:**
```bash
blender
# File → Import → Wavefront (.obj)
# Select: terrain.obj
```

**MeshLab:**
```bash
meshlab terrain.obj
```

**CloudCompare:**
```bash
cloudcompare terrain.obj
```

**Online:**
- Upload to https://3dviewer.net/
- Drag & drop `terrain.obj` + `texture.png`

### Output Files

```bash
workspace/
├── terrain.obj              # 3D mesh (Wavefront OBJ format, ~55MB)
├── terrain.mtl              # Material file (references texture)
├── terrain.iv               # Open Inventor format mesh (~47MB)
├── terrain.lbl              # PDS4 metadata label (~5KB)
├── texture.png              # Texture image (converted from VICAR)
├── pointcloud_filtered.xyz  # XYZ point cloud (rover filtered)
├── pointcloud.xyz           # XYZ point cloud (unfiltered)
├── disparity.img            # Refined disparity map (VICAR format)
├── disparity_init.img       # Initial disparity map (VICAR format)
└── left.vic, right.vic      # Input stereo pair
```

## Toolkit Management

### Status and Diagnostics

```bash
# Show container status
toolkit-status

# Check running container
docker ps | grep vicar-sidecar

# View container logs
docker logs vicar-sidecar

# Verify MARS calibration
toolkit-verify-calib
```

### Interactive Shell

```bash
# Open bash inside container
toolkit-shell

# Now inside container:
pwd  # → /workspace
ls   # See workspace files
exit
```

### Container Control

```bash
# Restart container (after config changes)
toolkit-restart

# Stop container
toolkit-stop

# Re-activate (restarts if stopped)
cd .. && cd -
direnv allow
```

### Deactivation

```bash
# Leave directory - commands disappear from PATH
cd ..

# Container keeps running in background
docker ps | grep vicar-sidecar  # Still running

# Re-enter - commands immediately available
cd vicar-native-toolkit
which marsmesh  # Works again!
```

## Configuration

### MARS Calibration

Edit `.envrc.local`:

```bash
# Container settings
CONTAINER_NAME="vicar-sidecar"
CONTAINER_IMAGE="ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource"

# MARS calibration (required for stereo processing)
MARS_CONFIG_PATH="/path/to/mars_calibration_m20"
```

Then reload:

```bash
direnv allow
toolkit-restart
toolkit-verify-calib
```

### Custom Container Image

```bash
# Edit .envrc.local
CONTAINER_IMAGE="myregistry/vicar:custom"

# Restart
toolkit-restart
```

## Troubleshooting

### "direnv: error .envrc is blocked"

```bash
cd vicar-native-toolkit
direnv allow
```

### "VICAR commands not found"

```bash
# Check if container is running
docker ps | grep vicar-sidecar

# Restart toolkit
toolkit-restart

# Re-enter directory
cd .. && cd -
```

### "Container not running"

```bash
# Check Docker is running
docker ps

# Remove old container
docker rm -f vicar-sidecar

# Re-activate
cd .. && cd vicar-native-toolkit
direnv allow
```

### "marscorr: command not found"

```bash
# Check wrappers generated
ls .direnv/wrappers/ | wc -l

# If < 500, regenerate:
toolkit-restart
```

### "Can't open display" (macOS)

```bash
# Start XQuartz
open -a XQuartz

# Allow connections
xhost +localhost

# Restart container
toolkit-restart
```

### Commands run but produce no output

```bash
# Check current directory
pwd
# Must be in workspace/ or subdirectory

# Or use absolute paths
cd vicar-native-toolkit/workspace
marsmesh inp=../data/pointcloud.xyz out=terrain.obj
```

## Performance Tips

### Speed Comparison

| Method | Command Latency | Container Startup |
|--------|----------------|-------------------|
| **vicar-native-toolkit** | ~50-100ms | 0ms (persistent) |
| docker run (per-command) | ~50-100ms | ~500-1000ms |
| Native binary | ~10-20ms | 0ms |

**Advantage:** 10-30x faster than `docker run` per command!

### Optimize Stereo Processing

**Use windowed/subframe images:**
```bash
# 1280x960 subframe: ~5-10 minutes
# 5120x3840 full-res: ~30-60 minutes
```

**Adjust correlation parameters:**
```bash
# Faster (lower quality)
marscorr \( left.vic right.vic \) disp.img \
  template=11 search=31  # Smaller templates = faster

# Slower (higher quality)
marscorr \( left.vic right.vic \) disp.img \
  template=21 search=71  # Larger templates = better
```

### Parallel Processing

```bash
# Process multiple stereo pairs in parallel
marscorr \( pair1_left.vic pair1_right.vic \) disp1.img &
marscorr \( pair2_left.vic pair2_right.vic \) disp2.img &
marscorr \( pair3_left.vic pair3_right.vic \) disp3.img &
wait
```

## Architecture

### How It Works

```
User types: marsmesh inp=data.xyz out=mesh.obj
     ↓
Shell finds: .direnv/wrappers/marsmesh (symlink)
     ↓
Points to: .direnv/vicar-exec
     ↓
vicar-exec detects command: "marsmesh" (from $0)
     ↓
Runs: docker exec -i vicar-sidecar marsmesh inp=data.xyz out=mesh.obj
     ↓
Container executes: /usr/local/bin/marsmesh
     ↓
Output returns: to user terminal
```

**Key advantages:**
- ✓ Single wrapper script for all commands
- ✓ Symlink-based routing (fast, ~1MB disk)
- ✓ Persistent container (no startup delay)
- ✓ Transparent to user (no Docker syntax)

### Directory Structure

```
vicar-native-toolkit/
├── .envrc                  # direnv activation script
├── .envrc.local            # User configuration (MARS calibration, etc.)
├── .direnv/                # Auto-generated (gitignored)
│   ├── vicar-exec          # Universal command wrapper
│   ├── toolkit-utils       # Utility commands (toolkit-status, etc.)
│   └── wrappers/           # 550+ symlinks to vicar-exec
│       ├── marsmesh → vicar-exec
│       ├── marsxyz → vicar-exec
│       ├── marscorr → vicar-exec
│       └── ...
├── workspace/              # Working directory (mounted to container)
│   └── ...
├── bootstrap.sh            # One-command setup
└── README.md
```

### Container Mounts

```
Host                                    Container
----                                    ---------
vicar-native-toolkit/workspace/    →    /workspace
/path/to/mars_calibration_m20/     →    /mars_config
```

## Example Workflows

### Workflow 1: Quick Test with Pre-computed XYZ

```bash
cd vicar-native-toolkit
direnv allow
cd workspace

# Copy existing XYZ and texture
cp /data/mars/pointcloud.xyz .
cp /data/mars/texture_image.vic texture.vic

# Generate mesh (fast!)
marsmesh inp=pointcloud.xyz out=terrain.obj \
  in_skin=texture.vic \
  x_subsample=2 y_subsample=2  # Downsample for speed

# View
meshlab terrain.obj
```

**Time:** ~30 seconds

### Workflow 2: Full Pipeline from Stereo Pair

```bash
cd vicar-native-toolkit/workspace

# Copy stereo images
cp /data/mars/NLF_*01_195J01.VIC left.vic
cp /data/mars/NLF_*04_195J01.VIC right.vic

# Run pipeline
marscorr \( left.vic right.vic \) disp_init.img template=15 search=51 quality=0.2
marscor3 \( left.vic right.vic \) disp.img in_disp=disp_init.img template=11 search=31 quality=0.4
marsxyz \( left.vic right.vic \) pc.xyz disp=disp.img
marsrfilt inp=pc.xyz out=pc_filtered.xyz
marsmesh inp=pc_filtered.xyz out=terrain.obj in_skin=right.vic
vicario right.vic texture.png

# View
blender terrain.obj
```

**Time:** ~15-20 minutes

### Workflow 3: Batch Processing Multiple Pairs

```bash
cd vicar-native-toolkit/workspace

# Process all stereo pairs in directory
for left in /data/mars/*01_*.VIC; do
  right="${left/01_/04_}"  # Replace 01_ with 04_
  base=$(basename "$left" .VIC | sed 's/_01_.*$//')
  
  echo "Processing: $base"
  cp "$left" "${base}_left.vic"
  cp "$right" "${base}_right.vic"
  
  marscorr \( "${base}_left.vic" "${base}_right.vic" \) "${base}_disp.img" template=15 search=51 quality=0.2 &
done

wait  # Wait for all parallel jobs
echo "All disparity maps generated!"
```

## Advanced Features

### Custom Working Directory

```bash
# Toolkit auto-resolves relative paths
cd vicar-native-toolkit/workspace/project1
marsmesh inp=../shared/data.xyz out=mesh.obj
# Works! Paths resolved relative to workspace mount
```

### Using toolkit-shell for Interactive Work

```bash
toolkit-shell

# Now inside container:
cd /workspace
ls
gen out=test.img nl=100 ns=100
hist inp=test.img
exit
```

### Accessing Container Environment Variables

```bash
toolkit-shell

# Check VICAR environment
echo $V2TOP
echo $MARS_CONFIG_PATH
echo $PATH
```

## Next Steps

- **[Full Toolkit README](README.md)** - Complete documentation
- **[Configuration Guide](docs/CONFIGURATION.md)** - Advanced setup options
- **[Mounting Data](docs/MOUNTING-DATA.md)** - Volume mount configuration
- **[Open Source Build](docs/OPENSOURCE-BUILD.md)** - Build from source

## Key Takeaways

✅ **Native feeling** - No Docker syntax in commands  
✅ **Fast execution** - Persistent container, no startup delay  
✅ **Auto-discovery** - 550+ commands automatically available  
✅ **Transparent** - Users don't need to know Docker  
✅ **Flexible** - Works with custom images and calibration data  

**Ready to generate Mars terrain meshes!** 🚀
