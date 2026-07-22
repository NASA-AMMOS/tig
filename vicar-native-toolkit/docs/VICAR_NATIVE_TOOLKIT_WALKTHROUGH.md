# VICAR Native Toolkit Walkthrough - Complete Setup for TIG Demo

**Goal:** Set up vicar-native-toolkit to work with the terrain-intelligence-generator:opensource image for native-like command execution in the TIG demo.

**Time:** ~15-20 minutes (mostly building Docker images)

---

## Prerequisites

Before starting, ensure you have:

- ✅ **Docker Desktop** installed and running
- ✅ **direnv** installed (`brew install direnv` on macOS, `apt install direnv` on Linux)
- ✅ **Shell configured** with direnv hook (see below)
- ✅ **~5GB free disk space** for Docker images
- ✅ **XQuartz** (macOS only) for X11 forwarding

### Configure direnv in Your Shell

Add to your shell config file (`~/.zshrc` for zsh, `~/.bashrc` for bash):

```bash
# For bash
eval "$(direnv hook bash)"

# For zsh
eval "$(direnv hook zsh)"
```

Then reload your shell:
```bash
source ~/.zshrc  # or source ~/.bashrc
```

---

## Step 1: Navigate to Project

```bash
cd vicar-native-toolkit
```

**Verify location:**
```bash
pwd
ls -la
# Should show: .envrc, workspace/, DEMO.md, README.md, etc.
```

---

## Step 2: Build the TIG Demo Docker Image

The TIG demo uses the opensource terrain-intelligence-generator image with VICAR v5.0.

```bash
# Navigate to the docker directory
cd ../terrain-intelligence-generator/docker

# Build the opensource image
docker build --platform linux/amd64 -t terrain-intelligence-generator:opensource .

# Return to toolkit directory
cd ../../vicar-native-toolkit
```

**Expected output:**
```
✅ Build successful!
Image created: terrain-intelligence-generator:opensource
Size: ~3.12GB
```

**Time:** ~3-5 minutes

**Verify image built:**
```bash
docker images | grep terrain-intelligence-generator:opensource
```

Should show:
```
terrain-intelligence-generator:opensource    latest    <image-id>    3.12GB
```

---

## Step 3: Review Configuration (Optional)

The toolkit comes with a default configuration. You can create a local config:

```bash
cat > .envrc.local << 'EOF'
# Local configuration for vicar-native-toolkit
export CONTAINER_IMAGE="terrain-intelligence-generator:opensource"
export MARS_CONFIG_PATH="/path/to/mars_calibration"
EOF
```

**Key settings:**
- `CONTAINER_IMAGE="terrain-intelligence-generator:opensource"` - Uses the TIG opensource image
- `MARS_CONFIG_PATH` - Path to MARS calibration files (required for stereo processing)
- `AUTO_DISCOVER_TOOLS=true` - Automatically finds all VICAR commands (default)

**This configuration is ready to use!** No changes needed.

---

## Step 4: Activate the Toolkit

Now activate the toolkit with direnv:

```bash
direnv allow
```

**What happens:**
1. 📝 Loads configuration from `.envrc.local` or defaults
2. 🔧 Detects your platform (macOS/Linux)
3. 📦 Starts `vicar-sidecar` container with terrain-intelligence-generator image
4. 📁 Mounts workspace directory
5. 🔨 Discovers and generates wrappers for ~543 VICAR commands
6. ✅ Adds wrappers to your PATH

**Expected output:**
```
[vicar-toolkit] Activating VICAR Native Toolkit...
[vicar-toolkit] Image: terrain-intelligence-generator:opensource
[vicar-toolkit] Container 'vicar-sidecar' is already running
[vicar-toolkit] Auto-discovering VICAR commands...
[vicar-toolkit] Found 543 commands
[vicar-toolkit] Generated 543 symlinks to vicar-exec
[vicar-toolkit] Created 4 utility command symlinks
[vicar-toolkit] ✅ Toolkit activated! VICAR commands now available.
[vicar-toolkit] Try: gen, label, marsmap, toolkit-shell, toolkit-status

Available commands:
  toolkit-status    - Show configuration and container status
  toolkit-shell     - Open interactive shell in container
  toolkit-stop      - Stop and remove container
  toolkit-restart   - Restart container with new configuration
  toolkit-update    - Pull latest image and recreate container

VICAR tools: 543 commands available
Working directory: <current-path>/vicar-native-toolkit/workspace
```

**Time:** ~30-60 seconds

---

## Step 5: Verify Wrapper Generation

If auto-discovery found 0 tools (due to timing), manually generate wrappers:

```bash
# Check current wrappers
ls .direnv/wrappers/ | wc -l
```

**If less than 543 wrappers**, regenerate them:

```bash
# Clean and regenerate
rm -rf .direnv/wrappers/*
toolkit-restart
cd .. && cd -
```

**Expected output:**
```
[vicar-toolkit] Found 543 commands
[vicar-toolkit] Generated 543 symlinks to vicar-exec
✅ Generated 543 wrappers in .direnv/wrappers
```

**Verify critical commands:**
```bash
ls .direnv/wrappers/ | grep -E "^(gen|label|hist|marscorr|marsxyz|marsmesh)$"
```

Should show all 6 commands.

---

## Step 6: Test Native Command Execution

Test that commands work like native CLI tools:

### Test 1: Basic VICAR Command

```bash
cd workspace

# Generate a test image (NO Docker syntax!)
gen out=test.vic nl=512 ns=512
```

**Expected output:**
```
Beginning VICAR task GEN
GEN Version 2019-05-28
GEN task completed
```

**✅ Success!** The `gen` command worked like a native CLI tool.

### Test 2: View Histogram

```bash
hist inp=test.vic
```

**Expected output:**
```
Beginning VICAR task HIST
*** HIST version 2017-08-08 ***

Bin Width = 1.0
  0    1
  1    2  *
  2    3  *
  ...
```

**✅ Success!** Commands work without any Docker syntax.

### Test 3: Check Container Status

```bash
toolkit-status
```

**Expected output:**
```
======================================================================
VICAR Native Toolkit Status
======================================================================

Container: vicar-sidecar
Image: terrain-intelligence-generator:opensource
Status: Up X seconds

Mounts:
  <toolkit-path>/workspace -> /workspace

Wrappers: 547 commands in .direnv/wrappers
```

**✅ Success!** Toolkit is configured and running.

---

## Step 7: Verify Mars Commands

Test that Mars processing commands are available:

```bash
# Check if Mars commands exist
ls .direnv/wrappers/ | grep ^mars | head -10
```

**Expected output:**
```
marsautoloco
marsautotie
marscorr
marscor3
marsdisparity
marsmesh
marsrfilt
marsxyz
...
```

### Test Mars Command Wrapper

```bash
# Test that marscorr wrapper exists and is executable
which marsmesh
file $(which marsmesh)
```

**Expected output:**
```
<toolkit-path>/.direnv/wrappers/marsmesh

<toolkit-path>/.direnv/wrappers/marsmesh: symbolic link to ../vicar-exec
```

**✅ Success!** Mars commands have native-like wrappers.

---

## Step 8: Test with Real Mars Data

If you have Mars stereo images or XYZ point clouds, you can copy them to the workspace:

```bash
cd workspace

# Copy data files (adjust paths as needed)
cp /path/to/your/left.VIC left_edr.vic
cp /path/to/your/right.VIC right_edr.vic
# or
cp /path/to/your/pointcloud.xyz .

ls -lh *.vic *.xyz
```

---

## Step 9: Test Label Command

```bash
cd workspace

# Generate a test image first
gen out=test.vic nl=100 ns=100

# View file info
file test.vic
```

**Expected output:**
```
test.vic: VICAR image data, 8 bits  = VAX byte
```

**✅ This confirms the toolkit is working!** VICAR commands execute natively.

---

## Step 10: Final Verification Checklist

Run through this checklist to ensure everything is ready:

```bash
# 1. Container running?
docker ps | grep vicar-sidecar
# ✅ Should show: vicar-sidecar   Up X minutes

# 2. Wrappers generated?
ls .direnv/wrappers/ | wc -l
# ✅ Should show: 543+ wrappers

# 3. Key commands available?
which gen hist label marscorr marsxyz marsmesh
# ✅ Should show: .direnv/wrappers/<command> for each

# 4. Basic VICAR command works?
gen out=test.vic nl=100 ns=100 2>&1 | grep "GEN task completed"
# ✅ Should show: GEN task completed

# 5. Mars commands available?
ls .direnv/wrappers/ | grep ^mars | wc -l
# ✅ Should show: 109 Mars commands

# 6. Data files accessible? (if copied in Step 8)
ls -lh *.vic *.xyz 2>/dev/null | wc -l
# ✅ Should show: number of files copied

# 7. Toolkit status?
toolkit-status | grep "Status:"
# ✅ Should show: Status: Up X seconds

# 8. Container running?
docker ps | grep vicar-sidecar
# ✅ Should show: vicar-sidecar   Up X seconds
```

**All checks passed?** You're ready for the demo! 🎉

---

## Troubleshooting

### Issue: "direnv: command not found"

**Solution:** Install direnv:
```bash
# macOS
brew install direnv

# Linux
sudo apt install direnv

# Add to shell config
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
source ~/.zshrc
```

### Issue: "Docker image not found"

**Solution:** Build the opensource image:
```bash
cd ../terrain-intelligence-generator/docker
docker build --platform linux/amd64 -t terrain-intelligence-generator:opensource .
```

### Issue: "Container fails to start"

**Solution:** Check Docker and restart:
```bash
# Check Docker is running
docker ps

# If container exists but stopped
docker rm vicar-sidecar

# Restart toolkit
toolkit-restart
cd .. && cd -
```

### Issue: "No wrappers generated" or "Found 0 executables"

**Solution:** Manually regenerate wrappers:
```bash
# Restart toolkit
toolkit-restart
cd .. && cd -

# Check wrapper count
ls .direnv/wrappers/ | wc -l
```

### Issue: "Commands not in PATH"

**Solution:** Reload direnv:
```bash
direnv reload
# Or exit and re-enter directory
cd .. && cd -
```

### Issue: "XQuartz errors" (macOS only)

**Solution:** Start XQuartz manually:
```bash
open -a XQuartz
xhost +localhost
```

---

## What You've Accomplished

✅ **Built terrain-intelligence-generator:opensource image** with VICAR v5.0  
✅ **Configured toolkit** for TIG demo  
✅ **Started long-running container** for fast command execution  
✅ **Generated 543+ wrapper scripts** for native-like commands  
✅ **Tested basic VICAR commands** (gen, hist, label)  
✅ **Verified Mars commands available** (marscorr, marsxyz, marsmesh, etc.)  
✅ **Prepared workspace** for Mars data processing  

---

## Next Steps: Run Mesh Generation Demo

Now that the toolkit is ready, you can run the mesh generation demo:

### Run the Full Stereo Pipeline

The TIG demo script will run the complete pipeline from stereo images to 3D mesh:

```bash
cd ..

# Run with stereo pair (~10-15 minutes)
./demo-mesh-native-toolkit.sh \
  --stereo-left /path/to/left.VIC \
  --stereo-right /path/to/right.VIC
```

### Or Run Commands Manually (Native Style)

Follow the step-by-step commands in DEMO.md:

```bash
cd vicar-native-toolkit/workspace

# Copy stereo pair
cp /path/to/left.VIC left.vic
cp /path/to/right.VIC right.vic

# Run stereo correlation
marscorr \( left.vic right.vic \) disparity_init.img template=15 search=51 quality=0.2
marscor3 \( left.vic right.vic \) disparity.img in_disp=disparity_init.img template=11 search=31 quality=0.4

# Generate XYZ point cloud
marsxyz \( left.vic right.vic \) pointcloud.xyz disp=disparity.img

# Filter rover hardware
marsrfilt inp=pointcloud.xyz out=pointcloud_filtered.xyz

# Generate mesh
marsmesh inp=pointcloud_filtered.xyz out=terrain.obj \
  in_skin=right.vic \
  x_subsample=1 y_subsample=1 \
  range_min=0.2 range_mid=100 range_max=100 \
  lod_levels=10 max_angle=87.5 \
  res_min=3000 res_max=500000 density=1 -adaptive \
  maxgap=5
```

**No Docker syntax needed!** Commands work like native CLI tools.

---

## Reference: Key Commands

### Toolkit Management

```bash
toolkit-status     # Show configuration and container status
toolkit-shell      # Open interactive shell in container
toolkit-restart    # Restart container
toolkit-stop       # Stop and remove container
```

### Container Operations

```bash
# Check container
docker ps | grep vicar-sidecar

# View logs
docker logs vicar-sidecar

# Execute command in container
docker exec vicar-sidecar <command>
```

### Wrapper Inspection

```bash
# List all wrappers
ls .direnv/wrappers/

# View wrapper implementation
cat .direnv/wrappers/marscorr

# Check command availability
which gen hist marscorr
```

---

## Architecture Diagram

```
User Command (e.g., "marscorr ...")
         ↓
Shell finds wrapper on PATH
         ↓
~/.direnv/wrappers/marscorr
         ↓
docker exec vicar-sidecar marscorr ...
         ↓
Long-running container (fast!)
         ↓
VICAR command executes
         ↓
Result returns to user
```

**Key Point:** User never sees Docker syntax - it all happens transparently!

---

## Summary

You've successfully set up vicar-native-toolkit to provide **native-like command execution** for 543 VICAR commands including all Mars processing tools. The toolkit:

- ✅ **Feels native** - No Docker syntax in user commands
- ✅ **Works fast** - Long-running container (~50-100ms latency)
- ✅ **Supports VICAR v5.0** - Open source build with Mars tools
- ✅ **Auto-discovers commands** - 543+ wrappers generated automatically
- ✅ **Demo-ready** - All components tested and validated

**Ready to run the TIG mesh generation demo with native-like VICAR commands!** 🚀

---

**Document Version:** 2.0  
**Last Updated:** June 29, 2026  
**Toolkit Version:** Symlink-based wrapper system  
**Target Image:** terrain-intelligence-generator:opensource (VICAR v5.0)
