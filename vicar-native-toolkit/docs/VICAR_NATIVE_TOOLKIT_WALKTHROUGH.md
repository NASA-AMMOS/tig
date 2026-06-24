# VICAR Native Toolkit Walkthrough - Complete Setup for TIG Demo

**Goal:** Set up vicar-native-toolkit to work with the M20-G87 VICAR build for native-like command execution in the TIG demo.

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
cd /Users/han/IdeaProjects/MIPL/vicar/vicar-native-toolkit
```

**Verify location:**
```bash
pwd
ls -la
# Should show: .envrc, docker/, scripts/, workspace/, etc.
```

---

## Step 2: Build the TIG Demo Docker Image

The TIG demo image extends the base VICAR image with Java vicario for image format conversion.

```bash
# Build the TIG demo image
./scripts/build-tig-demo-image.sh
```

**Expected output:**
```
✅ Build successful!
Image created: vicar-tools:tig-demo
Size: ~1.36GB
```

**Time:** ~3-5 minutes

**Verify image built:**
```bash
docker images | grep vicar-tools:tig-demo
```

Should show:
```
vicar-tools:tig-demo    latest    <image-id>    1.36GB
```

---

## Step 3: Review Configuration (Optional)

The toolkit comes with a default configuration for the TIG demo image. Review it:

```bash
cat .envrc.config
```

**Key settings you'll see:**
- `CONTAINER_IMAGE="vicar-tools:tig-demo"` - Uses the TIG demo image
- `VICAR_INSTALL_PREFIX="/usr/local/vicar/m20-g87"` - M20-G87 RPM build paths
- `AUTO_DISCOVER_TOOLS=true` - Automatically finds all VICAR commands
- `PARENT_DIR` mount - Makes `../project/` accessible as `/projects/` in container

**This configuration is ready to use!** No changes needed.

---

## Step 4: Activate the Toolkit

Now activate the toolkit with direnv:

```bash
direnv allow
```

**What happens:**
1. 📝 Loads configuration from `.envrc.config`
2. 🔧 Detects your platform (macOS/Linux)
3. 📦 Starts `vicar-sidecar` container with TIG demo image
4. 📁 Mounts workspace and parent directory
5. 🔨 Discovers and generates wrappers for ~700+ VICAR commands
6. ✅ Adds wrappers to your PATH

**Expected output:**
```
📝 Loading configuration from .envrc.config
🔧 VICAR Native Toolkit - Darwin detected
   Image: vicar-tools:tig-demo
   Container: vicar-sidecar
📦 Starting vicar-sidecar container...
📁 Mounting parent directory: /Users/han/IdeaProjects/MIPL/vicar -> /projects
✅ Container started successfully
🔨 Generating wrapper scripts...
🔍 Auto-discovering VICAR executables...
✅ Found XXX executables

✅ VICAR Native Toolkit activated!

Available commands:
  toolkit-status    - Show configuration and container status
  toolkit-shell     - Open interactive shell in container
  toolkit-stop      - Stop and remove container
  toolkit-restart   - Restart container with new configuration

VICAR tools: XXX commands available
Working directory: /Users/han/IdeaProjects/MIPL/vicar/vicar-native-toolkit/workspace
```

**Time:** ~30-60 seconds

---

## Step 5: Verify Wrapper Generation

If auto-discovery found 0 tools (due to timing), manually generate wrappers:

```bash
# Check current wrappers
ls .direnv/wrappers/ | wc -l
```

**If less than 700 wrappers**, regenerate them:

```bash
# Clean and regenerate
rm -rf .direnv/wrappers/*
./.direnv/generate-wrappers.sh
```

**Expected output:**
```
Discovering executables...
Found 782 executables, generating wrappers...
  Generated 100 wrappers...
  Generated 200 wrappers...
  ...
  Generated 700 wrappers...
✅ Generated 782 wrappers in .direnv/wrappers
```

**Verify critical commands:**
```bash
ls .direnv/wrappers/ | grep -E "^(gen|label|hist|marscorr|marsxyz)$"
```

Should show all 5 commands.

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
Image: vicar-tools:tig-demo
Status: running

Mounts:
  /Users/han/IdeaProjects/MIPL/vicar/vicar-native-toolkit/workspace -> /workspace
  /Users/han/IdeaProjects/MIPL/vicar -> /projects

Wrappers: XXX commands in .direnv/wrappers

VICAR Paths (inside container):
  BIN: /usr/local/bin:/usr/local/vicar/m20-g87/p2/lib/x86-64-linx:/usr/local/vicar/m20-g87/mars/lib/x86-64-linx:...
  LIB: /usr/local/vicar/m20-g87/olb/x86-64-linx:/usr/local/vicar/m20-g87/mars/lib/x86-64-linx:...
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
marscorr
marsdisparity
marsmap
marsrad
marstie
marsxyz
...
```

### Test Mars Command Wrapper

```bash
# Test that marscorr wrapper exists and is executable
which marscorr
cat $(which marscorr) | head -20
```

**Expected output:**
```
/Users/han/IdeaProjects/MIPL/vicar/vicar-native-toolkit/.direnv/wrappers/marscorr

#!/usr/bin/env bash
# Wrapper for: marscorr

TTY_FLAG=""
[ -t 0 ] && [ -t 1 ] && TTY_FLAG="-t"

exec docker exec -i ${TTY_FLAG} \
    -e DISPLAY=host.docker.internal:0 \
    -e PATH="/usr/local/bin:..." \
    -e LD_LIBRARY_PATH="/usr/local/vicar/m20-g87/..." \
    -w /workspace \
    "vicar-sidecar" \
    marscorr "$@"
```

**✅ Success!** Mars commands have native-like wrappers.

---

## Step 8: Prepare for TIG Demo

Now set up access to the TIG demo directory:

```bash
# Create symlink to demo directory (if not already present)
cd workspace
ln -sf ../../vicar-tig-demo demo
ls -la demo
```

**Verify access:**
```bash
# Check that demo files are accessible from container
docker exec vicar-sidecar ls -la /workspace/demo 2>&1 | head -5
```

**Note:** Due to mount limitations, you may need to copy demo data to workspace or access via the `/projects` mount.

### Option A: Copy Demo Data to Workspace

```bash
cd workspace
cp -r ../../vicar-tig-demo/data/input/edrs/ ./edrs/
ls -lh edrs/
```

### Option B: Access via /projects Mount

The parent directory is mounted at `/projects`, so:
- Host: `/Users/han/IdeaProjects/MIPL/vicar/vicar-tig-demo/data/input/edrs/`
- Container: `/projects/vicar-tig-demo/data/input/edrs/`

---

## Step 9: Test with Real M20 EDR Files

Copy one EDR stereo pair to workspace for testing:

```bash
cd workspace

# Copy EDR files
cp ../../vicar-tig-demo/data/input/edrs/NRF_1812_0827803370_941EDR_N0870268NCAM02812_01_195J01.VIC left_edr.vic
cp ../../vicar-tig-demo/data/input/edrs/NRF_1812_0827803370_941EDR_N0870268NCAM02812_04_195J01.VIC right_edr.vic

ls -lh *_edr.vic
```

**Expected output:**
```
-rw-r--r--  1 han  staff   7.2M  left_edr.vic
-rw-r--r--  1 han  staff   7.2M  right_edr.vic
```

### Test Label Command (Mars Metadata)

```bash
# This will show TAE subcommand error, but proves command works
label left_edr.vic 2>&1 | head -5
```

**Expected output:**
```
[TAE-SUBREQ] Subcommand is required for 'LABEL'.
```

**✅ This is expected!** VICAR's label command requires subcommands. The wrapper is working.

---

## Step 10: Final Verification Checklist

Run through this checklist to ensure everything is ready:

```bash
# 1. Container running?
docker ps | grep vicar-sidecar
# ✅ Should show: vicar-sidecar   Up X minutes

# 2. Wrappers generated?
ls .direnv/wrappers/ | wc -l
# ✅ Should show: 700+ wrappers

# 3. Key commands available?
which gen hist label marscorr marsxyz
# ✅ Should show: .direnv/wrappers/<command> for each

# 4. Basic VICAR command works?
gen out=test.vic nl=100 ns=100 2>&1 | grep "GEN task completed"
# ✅ Should show: GEN task completed

# 5. Mars commands available?
ls .direnv/wrappers/ | grep ^mars | wc -l
# ✅ Should show: 70+ Mars commands

# 6. EDR files accessible?
ls -lh *_edr.vic 2>/dev/null | wc -l
# ✅ Should show: 2 (if copied in Step 9)

# 7. Toolkit status?
toolkit-status | grep "Status:"
# ✅ Should show: Status: running

# 8. Java vicario available?
docker exec vicar-sidecar which vicario
# ✅ Should show: /usr/local/bin/vicario

docker exec vicar-sidecar java -version
# ✅ Should show: OpenJDK 11
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

**Solution:** Build the TIG demo image:
```bash
./scripts/build-tig-demo-image.sh
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
# Stop container
toolkit-stop

# Remove old wrappers
rm -rf .direnv/wrappers/*

# Restart (will regenerate wrappers)
cd .. && cd -

# If still 0, use manual generation
./.direnv/generate-wrappers.sh
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

✅ **Built vicar-tools:tig-demo image** with Java vicario  
✅ **Configured toolkit** for M20-G87 VICAR build  
✅ **Started long-running container** for fast command execution  
✅ **Generated 700+ wrapper scripts** for native-like commands  
✅ **Tested basic VICAR commands** (gen, hist, label)  
✅ **Verified Mars commands available** (marscorr, marsxyz, etc.)  
✅ **Prepared real M20 EDR data** for demo  
✅ **Validated Java vicario** for image format conversion  

---

## Next Steps: Run the TIG Demo

Now that the toolkit is ready, you can:

### Option 1: Run Demo Scripts with Native Commands

The TIG demo scripts will automatically use the wrappers:

```bash
cd ../vicar-tig-demo

# Stage 2: Stereo Matching (uses marscorr wrapper internally)
python3 scripts/02-stereo-match.py \
  --left data/input/edrs/NRF_1812_0827803370_941EDR_N0870268NCAM02812_01_195J01.VIC \
  --right data/input/edrs/NRF_1812_0827803370_941EDR_N0870268NCAM02812_04_195J01.VIC \
  --output data/cache/disparity.vic \
  -v
```

The Python script calls `subprocess.run(["marscorr", ...])` which finds the wrapper on PATH!

### Option 2: Run Commands Directly (Native Style)

```bash
cd vicar-native-toolkit/workspace

# Direct command usage (native style!)
gen out=left_small.vic nl=400 ns=400
gen out=right_small.vic nl=400 ns=400

# Resize EDR files
size inp=left_edr.vic out=left_small.vic nl=400 ns=400
size inp=right_edr.vic out=right_small.vic nl=400 ns=400

# Run stereo correlation (may take several minutes)
marscorr inp=(left_small.vic,right_small.vic) out=disparity.vic
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

You've successfully set up vicar-native-toolkit to provide **native-like command execution** for 700+ VICAR commands including all Mars processing tools. The toolkit:

- ✅ **Feels native** - No Docker syntax in user commands
- ✅ **Works fast** - Long-running container (~50-100ms latency)
- ✅ **Supports M20-G87** - RPM-based VICAR build with Mars tools
- ✅ **Auto-discovers commands** - 700+ wrappers generated automatically
- ✅ **Python-friendly** - Scripts just call commands via subprocess
- ✅ **Demo-ready** - All components tested and validated

**Ready to run the TIG demo with native-like VICAR commands!** 🚀

---

**Document Version:** 1.0  
**Last Updated:** March 31, 2026  
**Toolkit Version:** Configurable image support  
**Target Image:** vicar-tools:tig-demo (M20-G87 + Python deps)
