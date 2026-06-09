# Terrain Intelligence Generator - Demo Commands

Complete demonstration of the terrain-intelligence-generator Docker image functionality using direct Docker commands. This guide covers all core VICAR capabilities without requiring additional tooling.

For a native-like command experience with docker-compose, see [vicar-native-toolkit/DEMO_COMMANDS.md](./vicar-native-toolkit/DEMO_COMMANDS.md).

## Prerequisites

- Docker Engine 20.10+ or Docker Desktop
- Access to the terrain-intelligence-generator image

## Image Availability

The demos use the open-source terrain-intelligence-generator image:

```bash
# Check if image is available locally
docker images | grep terrain-intelligence-generator

# If not available, pull from GitHub Container Registry
docker pull ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource

# Or build from source (see TERRAIN-INTELLIGENCE-GENERATOR.md)
```

---

## Demo Steps - Direct Docker Usage

**Note for SELinux systems (Fedora, RHEL, CentOS):** If using volume mounts and getting "Permission denied" errors, add `:Z` flag: `-v /path/to/dir:/workspace:Z`

### Step 1: Start Long-Running Container

Using a long-running container (sidecar pattern) provides better performance than `docker run` per command.

```bash
# Start container in background
docker run -d \
  --name vicar-demo \
  ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource \
  tail -f /dev/null

# Verify container is running
docker ps | grep vicar-demo
```

### Step 2: Test Basic VICAR Commands

Generate test images using the `gen` command:

```bash
# Generate small test image (64x64 pixels)
docker exec vicar-demo bash -c 'cd /tmp && gen test.vic 64 64'

# Verify file created
docker exec vicar-demo ls -lh /tmp/test.vic

# Generate larger test image (512x512 pixels)
docker exec vicar-demo bash -c 'cd /tmp && gen large.vic 512 512'

# Check both files
docker exec vicar-demo bash -c 'cd /tmp && ls -lh *.vic'
```

**Expected Output:**
```
Beginning VICAR task GEN
GEN Version 2019-05-28
GEN task completed
```

### Step 3: Test Image Operations

Test core VICAR image manipulation commands:

```bash
# Copy image
docker exec vicar-demo bash -c 'cd /tmp && copy test.vic test_copy.vic'

# Stretch image contrast
docker exec vicar-demo bash -c 'cd /tmp && stretch test.vic stretched.vic'

# List all created files
docker exec vicar-demo bash -c 'cd /tmp && ls -lh *.vic'
```

**Expected Output:**
- `copy`: Should complete with "COPY VERSION" message
- `stretch`: Shows histogram statistics and auto-stretch parameters

### Step 4: Test vicario Converter

The `vicario` tool converts VICAR images to common formats (PNG/JPEG/TIFF):

```bash
# Convert to PNG
docker exec vicar-demo vicario /tmp/test.vic /tmp/test.png

# Convert to JPEG
docker exec vicar-demo vicario /tmp/test.vic /tmp/test.jpg

# Convert to TIFF
docker exec vicar-demo vicario /tmp/test.vic /tmp/test.tiff

# Verify all conversions
docker exec vicar-demo bash -c 'cd /tmp && ls -lh test.*'
```

**Expected Output:**
```
Converting /tmp/test.vic to intermediate format...
Reading pixel data...
   Image dimensions: 64 x 64
Writing .PNG file...
✅ Success: /tmp/test.png (99 bytes)
   Dimensions: 64 x 64
```

### Step 5: Verify MARS Commands

MARS (Multi-mission Advanced Research and Science Software) tools for terrain processing:

```bash
# List all MARS commands (should show 74 total)
docker exec vicar-demo bash -c 'ls /usr/local/bin | grep "^mars"'

# Count MARS commands
docker exec vicar-demo bash -c 'ls /usr/local/bin | grep "^mars" | wc -l'

# Check specific MARS commands exist
docker exec vicar-demo bash -c 'which marsmap && which marscorr && which marsxyz'
```

**Expected Output:**
- 74 MARS commands total
- Includes: marsmap, marscorr, marsxyz, marsautotie, marsdisparity, etc.

### Step 6: Check All Available Commands

```bash
# Count total wrapper commands (should be 545)
docker exec vicar-demo bash -c 'ls /usr/local/bin | wc -l'

# List first 20 commands
docker exec vicar-demo bash -c 'ls /usr/local/bin | head -20'

# List sample of common VICAR commands
docker exec vicar-demo bash -c 'ls /usr/local/bin | grep -E "^(gen|copy|stretch)$"'
```

**Expected Output:**
- 545 total commands available
- Includes wrappers for all VICAR p2, TAE, and MARS programs

### Step 7: Check Environment and Data

Verify the VICAR environment and VISOR data availability:

```bash
# Check environment variables
docker exec vicar-demo bash -c 'echo "V2TOP=$V2TOP" && echo "WORKSPACE=$WORKSPACE" && echo "VICSYS=$VICSYS"'

# Check VISOR calibration data
docker exec vicar-demo bash -c 'ls -la $VISOR_CALIB | head -10'

# Check VISOR sample data
docker exec vicar-demo bash -c 'ls -la $VISOR_SAMPLES | head -10'

# Count VISOR files
docker exec vicar-demo bash -c 'find $VISOR_CALIB -type f | wc -l'
docker exec vicar-demo bash -c 'find $VISOR_SAMPLES -type f | wc -l'
```

**Expected Output:**
- V2TOP=/usr/local/vicar/dev
- WORKSPACE=/usr/local/vicar
- VICSYS=DEVELOPMENT
- VISOR_CALIB: 1,461 files
- VISOR_SAMPLES: 249 files

### Step 8: Test Java vicario

The vicario converter uses Java for VICAR image format conversion:

```bash
# Check Java version
docker exec vicar-demo java -version

# Check vicario is installed
docker exec vicar-demo which vicario

# Test vicario wrapper
docker exec vicar-demo bash -c 'ls /usr/local/bin/vicario.jar'
```

**Expected Output:**
- Java 11 (OpenJDK)
- vicario: /usr/local/bin/vicario
- vicario.jar found

### Step 9: Copy Files from Container to Host (Optional)

Extract generated images to your host system:

```bash
# Create output directory on host
mkdir -p ~/vicar-demo-output

# Copy generated images to host
docker cp vicar-demo:/tmp/test.vic ~/vicar-demo-output/
docker cp vicar-demo:/tmp/test.png ~/vicar-demo-output/
docker cp vicar-demo:/tmp/test.jpg ~/vicar-demo-output/

# Verify files on host
ls -lh ~/vicar-demo-output/
```

### Step 10: Interactive Shell (Optional)

Enter the container for interactive testing:

```bash
# Enter container
docker exec -it vicar-demo bash

# Once inside, you can run commands directly:
cd /tmp
gen mytest.vic 256 256
label mytest.vic
vicario mytest.vic mytest.png
exit
```

## Cleanup

```bash
# Stop and remove container
docker stop vicar-demo
docker rm vicar-demo

# Verify cleanup
docker ps -a | grep vicar-demo
```

---

## Alternative: Single-Command Usage

If you prefer not to keep a running container, use `docker run --rm`:

```bash
# Generate and list test image (container starts and stops)
docker run --rm ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource \
  bash -c 'cd /tmp && gen test.vic 64 64 && ls -lh test.vic'

# Generate, convert, and list
docker run --rm ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource \
  bash -c 'cd /tmp && gen test.vic 64 64 && vicario test.vic test.png && ls -lh test.*'

# Count MARS commands
docker run --rm ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource \
  bash -c 'ls /usr/local/bin | grep "^mars" | wc -l'
```

**Note:** This approach is slower due to container startup overhead but requires no cleanup.

---

## Using with Workspace Mounts

Mount a local directory to persist files between sessions:

```bash
# Create workspace directory
mkdir -p ./workspace

# Start container with workspace mount
docker run -d \
  --name vicar-demo \
  -v $(pwd)/workspace:/workspace \
  ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource \
  tail -f /dev/null

# Generate files in mounted workspace
docker exec vicar-demo bash -c 'cd /workspace && gen output.vic 512 512'
docker exec vicar-demo bash -c 'cd /workspace && vicario output.vic output.png'

# Files are now available on host
ls -lh ./workspace/

# Cleanup
docker stop vicar-demo && docker rm vicar-demo
```

---

## Summary of Test Coverage

✅ **Container Functionality**
- Container starts and runs correctly
- Environment variables set properly
- VICAR installation accessible at /usr/local/vicar/dev

✅ **VICAR Commands** (545 total)
- `gen` - Generate test images ✓
- `copy` - Copy images ✓
- `stretch` - Stretch image contrast ✓
- `label` - Display image labels
- `list` - List image contents
- `hist` - Display histogram

✅ **MARS Commands** (74 total)
- marsmap, marscorr, marsxyz ✓
- marsautotie, marsdisparity
- All accessible via wrappers

✅ **File Conversion**
- vicario: VICAR → PNG ✓
- vicario: VICAR → JPEG ✓
- vicario: VICAR → TIFF ✓

✅ **Python Integration**
- Python 3.9.25 available ✓
- Pillow 11.3.0 installed ✓
- vicario uses Pillow for conversions

✅ **Data Access**
- VISOR calibration files: 1,461 files ✓
- VISOR sample data: 249 files ✓

---

## Troubleshooting

### Container fails to start

```bash
# Check logs
docker logs vicar-demo

# Clean up and retry
docker system prune
docker run -d --name vicar-demo ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource tail -f /dev/null
```

### Permission errors with volume mounts

```bash
# SELinux systems (Fedora/RHEL/CentOS) - add :Z flag
docker run -d --name vicar-demo -v $(pwd)/workspace:/workspace:Z \
  ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource tail -f /dev/null

# Or work inside container without mounts (files persist until container removed)
docker exec vicar-demo bash -c 'cd /tmp && gen test.vic 64 64'
```

### Commands not found

```bash
# Check PATH
docker exec vicar-demo bash -c 'echo $PATH'

# List available commands
docker exec vicar-demo ls /usr/local/bin | head -20

# Verify VICAR installation
docker exec vicar-demo bash -c 'ls $V2TOP/p2/lib/x86-64-linx/ | head -10'
```

### Image not available

```bash
# Pull from GitHub Container Registry
docker pull ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource

# Or check available images
docker images | grep terrain
```

---

## Time Estimate

- Image pull/verification: 1-2 minutes
- Demo steps execution: 5-10 minutes
- **Total: 6-12 minutes**

---

## Next Steps

- **For native-like command experience**: See [vicar-native-toolkit/](./vicar-native-toolkit/)
- **For building from source**: See [TERRAIN-INTELLIGENCE-GENERATOR.md](./TERRAIN-INTELLIGENCE-GENERATOR.md)
- **For advanced workflows**: See [vicar-native-toolkit/QUICKREF.md](./vicar-native-toolkit/QUICKREF.md)
