# VICAR Native Toolkit - Demo Commands

Demonstration of native-like command execution using direnv and wrapper scripts. VICAR commands execute inside a Docker container but feel like they're running natively on your system - no `docker-compose exec` or `docker exec` prefix needed!

## Prerequisites

- Docker Engine 20.10+ or Docker Desktop
- direnv installed (`sudo apt install direnv` on Linux, `brew install direnv` on macOS)
- Shell hook configured (add `eval "$(direnv hook bash)"` to ~/.bashrc or ~/.zshrc)
- Access to terrain-intelligence-generator image

## Image Setup

```bash
# Navigate to toolkit directory
cd /path/to/tig/vicar-native-toolkit

# Check if terrain-intelligence-generator image is available
docker images | grep terrain-intelligence-generator

# If not available, pull from GitHub Container Registry
docker pull ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource
```

---

## Step 1: Activate the Toolkit

```bash
# Allow direnv to activate the environment
direnv allow
```

**Expected Output:**
```
[vicar-toolkit] Activating VICAR Native Toolkit...
[vicar-toolkit] Image: ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource
[vicar-toolkit] Creating new container 'vicar-sidecar'...
[vicar-toolkit] Container started successfully
[vicar-toolkit] Auto-discovering VICAR commands...
[vicar-toolkit] Found 545 commands
[vicar-toolkit] Generated 545 wrapper scripts
[vicar-toolkit] ✅ Toolkit activated! VICAR commands now available.
```

---

## Step 2: Navigate to Workspace

```bash
# Enter the workspace directory
cd workspace
```

All VICAR commands must be run from within the `workspace/` directory or its subdirectories.

---

## Step 3: Test Basic VICAR Commands

Now you can use VICAR commands directly, as if they were installed natively!

```bash
# Generate test image (64x64 pixels)
gen test.vic 64 64

# List the file
ls -lh test.vic

# Generate larger test image (512x512 pixels)
gen large.vic 512 512

# Check both files
ls -lh *.vic
```

**Expected Output:**
```
Beginning VICAR task GEN
GEN Version 2019-05-28
GEN task completed
```

**Key Feature:** No `docker-compose exec` or `docker exec` needed! Commands work like native CLI tools.

---

## Step 4: Test Image Operations

```bash
# Copy image
copy test.vic test_copy.vic

# Stretch image contrast
stretch test.vic stretched.vic

# List all VICAR images
ls -lh *.vic
```

---

## Step 5: Test vicario Converter

Convert VICAR images to common formats:

```bash
# Convert to PNG
vicario test.vic test.png

# Convert to JPEG
vicario test.vic test.jpg

# Convert to TIFF
vicario test.vic test.tiff

# Verify conversions
ls -lh test.*
```

**Expected Output:**
```
Converting test.vic to intermediate format...
Reading pixel data...
   Image dimensions: 64 x 64
Writing .PNG file...
✅ Success: test.png (99 bytes)
   Dimensions: 64 x 64
```

---

## Step 6: Verify MARS Commands

MARS commands are available as native-like wrappers:

```bash
# Test a MARS command exists
marsmap --help 2>&1 | head -5

# Or check specific commands work
type marsmap
type marscorr
type marsxyz
```

**Note:** 74 MARS commands are available. You can list them from the toolkit root with:
```bash
cd ..
ls .direnv/wrappers | grep "^mars" | head -20
cd workspace
```

---

## Step 7: Check Toolkit Status

```bash
# Check toolkit status
toolkit-status
```

**Expected Output:**
```
VICAR Native Toolkit Status:
  Container: vicar-sidecar
  Status: Up X minutes
  Wrappers: 549 commands
  Image: ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource
```

---

## Step 8: Interactive Container Shell (Optional)

Enter the container for direct interaction:

```bash
# Open interactive shell
toolkit-shell

# Inside container, run commands:
cd /workspace
gen interactive.vic 256 256
label interactive.vic
exit

# Files persist on host
ls -lh interactive.*
```

---

### Step 9: Leave Directory (Deactivate)

```bash
# Go back to parent directory
cd ../..
```

When you leave the `vicar-native-toolkit` directory, the wrapper commands are automatically removed from your PATH. The container keeps running in the background.

---

### Step 10: Re-enter Directory (Reactivate)

```bash
# Re-enter toolkit directory
cd vicar-native-toolkit

# Commands are instantly available again!
cd workspace
gen another.vic 512 512
```

The container is already running, so activation is instantaneous.

---

## Cleanup

### Stop Container

```bash
# From vicar-native-toolkit directory
toolkit-stop
```

### Restart Container

```bash
# Stop and remove container (will be recreated on next activation)
toolkit-restart

# Leave and re-enter directory
cd .. && cd vicar-native-toolkit
```

---

## Summary - Native-like Commands

### What You Learned

✅ Activate toolkit with `direnv allow`  
✅ Use VICAR commands directly (no docker prefix)  
✅ Commands work from `workspace/` directory  
✅ Files persist on host automatically  
✅ Leave directory to deactivate, re-enter to reactivate  

### Key Benefits

1. **Native feel**: Commands work like locally installed tools
2. **Fast**: Container stays running, no startup overhead
3. **Automatic**: direnv activates/deactivates on directory entry/exit
4. **Transparent**: 545 commands available instantly
5. **Persistent**: Workspace files always accessible on host

---

## Time Estimate

- Initial setup (direnv install): 2-3 minutes
- Image pull (if needed): 5-10 minutes
- Demo execution: 3-5 minutes
- **Total: 10-18 minutes (5-8 if image already available)**

---
