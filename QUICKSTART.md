# Quick Start - Running Demos with Your Data

## Option 1: Original Demo (Temporary Container)

Fast, one-time mesh generation from stereo pairs or XYZ files.

### With Pre-computed XYZ

```bash
./demo-mesh-generation-with-xyz.sh \
  --xyz /path/to/pointcloud.xyz \
  --texture /path/to/texture.img
```

**Time:** ~90 seconds

### With Stereo Pair

```bash
./demo-mesh-generation-with-xyz.sh \
  --stereo-left /path/to/NLM_*_FDR_*.VIC \
  --stereo-right /path/to/NRM_*_FDR_*.VIC
```

**Time:** ~10+ minutes (full resolution images)

**Requirements:**
- Left and right images from **same acquisition** (matching SCLK timestamp)
- Full-resolution or subframe images (not downsampled/thumbnails)
- MARS calibration files (auto-detected in `terrain-intelligence-generator/docker/mars_calibration_m20`)

**Output:** `workspace/terrain.obj`, `workspace/texture.png`

**Cleanup:**
```bash
docker stop tig-mesh-demo && docker rm tig-mesh-demo
```

---

## Option 2: Native Toolkit Demo (Persistent Container)

Native-looking commands for interactive development. Container stays running.

### One-time Setup

```bash
# 1. Install direnv
sudo apt install direnv  # Ubuntu/Debian
brew install direnv      # macOS

# 2. Add to shell (choose one)
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc

# 3. Restart shell
source ~/.bashrc  # or source ~/.zshrc

# 4. Trust the toolkit directory
cd vicar-native-toolkit
direnv allow
cd ..
```

### With Pre-computed XYZ

```bash
./demo-mesh-native-toolkit.sh \
  --xyz /path/to/pointcloud.xyz \
  --texture /path/to/texture.img
```

### With Stereo Pair

```bash
./demo-mesh-native-toolkit.sh \
  --stereo-left /path/to/NLM_*_FDR_*.VIC \
  --stereo-right /path/to/NRM_*_FDR_*.VIC
```

**Output:** `vicar-native-toolkit/workspace/terrain.obj`, `texture.png`

**Container Management:**
```bash
cd vicar-native-toolkit

# Check status
toolkit-status

# Open shell in container
toolkit-shell

# Stop container
toolkit-stop
```

---

## Where to Get Data

### Mars 2020 NavCam Stereo Pairs

**VISOR (Recommended):**
- https://mars.nasa.gov/mmgis-maps/M20/Layers/json/
- Look for `*_FDR_*.VIC` files (Full Data Record format)
- Download matching left (NLM) and right (NRM) pairs

**PDS Geosciences Node:**
- https://pds-geosciences.wustl.edu/missions/mars2020/
- Navigate to NCAM data products
- Download stereo pairs with matching SCLK timestamps

**Example filenames:**
```
Left:  NLM_1835_0829848458_777FDR_N0874924NCAM00230_0A02LLJ01.VIC
Right: NRM_1835_0829848458_777FDR_N0874924NCAM00230_0A02LLJ01.VIC
        ^^^^^^^^^^^^^^^^^^^^  <-- Must match (SCLK timestamp)
```

### Pre-computed XYZ Files

VISOR provides pre-computed XYZ point clouds:
- Search for `*_xyz_*.img` files
- Much faster than stereo processing

---

## Troubleshooting

### "MARS calibration not found"

```bash
# Check calibration location
ls terrain-intelligence-generator/docker/mars_calibration_m20/camera_models/

# If missing, calibration is included in the Docker image
# Or download from: https://github.com/NASA-AMMOS/VICAR
```

### "Stereo images don't match"

**Error:** Disparity calculation fails or produces garbage

**Solution:** Verify images are from same acquisition:
```bash
# Check SCLK timestamp in filename
# Must match exactly between left (NLM) and right (NRM)
```

### "direnv not allowed"

```bash
cd vicar-native-toolkit
direnv allow
```

### "Out of memory"

**Increase Docker memory:**
- Docker Desktop: Settings → Resources → Memory (recommend 16GB)

**Or use smaller images:**
- Use subframe/windowed images instead of full resolution
- Reduce marsmesh `res_max` parameter

### "Container won't start"

```bash
# Check Docker running
docker ps

# Remove stale container
docker stop vicar-sidecar && docker rm vicar-sidecar

# Re-enter toolkit directory
cd vicar-native-toolkit
cd .. && cd vicar-native-toolkit
```

---

## Comparison: Which Demo to Use?

| Feature | Original Demo | Native Toolkit |
|---------|--------------|----------------|
| **Setup** | None | direnv one-time setup |
| **Speed** | Container startup each run (~5s) | Instant (persistent) |
| **Use case** | One-off processing | Interactive development |
| **Cleanup** | Manual | Automatic (optional) |
| **Commands** | `docker exec ...` | Native-looking |
| **Best for** | Production pipelines | Exploration, testing |

---

## Example Workflows

### Quick Test with Sample Data

```bash
# Using existing workspace data
./demo-mesh-generation-with-xyz.sh \
  --xyz workspace/pointcloud.xyz \
  --texture workspace/texture.img
```

### Process Real Mars 2020 Data

```bash
# 1. Download stereo pair from VISOR
cd /tmp
wget https://mars.nasa.gov/.../NLM_1835_0829848458_777FDR_*.VIC
wget https://mars.nasa.gov/.../NRM_1835_0829848458_777FDR_*.VIC

# 2. Generate mesh
cd /path/to/tig
./demo-mesh-generation-with-xyz.sh \
  --stereo-left /tmp/NLM_*.VIC \
  --stereo-right /tmp/NRM_*.VIC

# 3. View mesh
# Import workspace/terrain.obj into Blender/MeshLab
```

### Interactive Exploration

```bash
# 1. Setup toolkit (one-time)
cd vicar-native-toolkit
direnv allow

# 2. Work interactively
cd workspace
gen out=test.img nl=100 ns=100
label test.img
marsmesh inp=../../../workspace/pointcloud.xyz out=custom.obj

# 3. Container stays running for next session
```

---

## Viewing Meshes

**Desktop Applications:**
- **Blender:** File → Import → Wavefront (.obj)
- **MeshLab:** File → Import Mesh
- **CloudCompare:** File → Open

**Online Viewer:**
- https://3dviewer.net/ (drag and drop .obj + .png)

**Command-line Inspection:**
```bash
# Count vertices
grep -c "^v " terrain.obj

# Count triangles
grep -c "^f " terrain.obj

# Check file size
ls -lh terrain.obj
```

---

## Next Steps

- Read full documentation: `docs/demos/mesh-generation.md`
- Explore VICAR commands: `toolkit-shell` then `ls /usr/local/bin`
- Customize processing: Edit marsmesh/marsxyz parameters in demo scripts
- Integrate into pipelines: Use as reference for your own scripts
