# Mounting Camera Models and External Data

This guide explains how to mount camera models, calibration files, mission data, and other external directories into the VICAR Native Toolkit container.

## Quick Start

### 1. Identify Your Data Locations

Camera models and calibration data are typically stored in:

- **V2CONFIG_PATH**: VICAR configuration path (camera models, .cahv/.cahvor files)
- **Mission Data**: Mars mission data (images, EDRs, RDRs)
- **Pointing Files**: Mars pointing files (usually in `/proj/mars/def` on JPL systems)

### 2. Edit `.envrc` Configuration

Open `.envrc` and uncomment/configure the data mount variables:

```bash
# ===== Camera Models and Calibration Data =====
# Uncomment and configure these paths to mount camera models and calibration data
CAMERA_MODELS_DIR="${V2CONFIG_PATH:-/path/to/camera/models}"  # Camera calibration files
MISSION_DATA_DIR="/data/missions"                              # Mission data (read-only)
POINT_FILES_DIR="/proj/mars/def"                               # Mars pointing files
```

### 3. Configure Your Paths

#### Option A: Use Environment Variables (Recommended)

Set environment variables in your shell profile (`~/.bashrc`, `~/.zshrc`):

```bash
# Add to ~/.zshrc or ~/.bashrc
export V2CONFIG_PATH="/path/to/your/camera/models"
export MISSION_DATA_PATH="/data/missions"
export POINT_FILES_PATH="/proj/mars/def"
```

Then update `.envrc`:

```bash
CAMERA_MODELS_DIR="${V2CONFIG_PATH}"
MISSION_DATA_DIR="${MISSION_DATA_PATH}"
POINT_FILES_DIR="${POINT_FILES_PATH}"
```

#### Option B: Hardcode Paths in `.envrc`

```bash
CAMERA_MODELS_DIR="/Users/han/vicar/config"
MISSION_DATA_DIR="/Users/han/data/missions"
POINT_FILES_DIR="/Users/han/mars/pointing"
```

### 4. Restart the Environment

```bash
# Stop existing container
docker stop vicar-sidecar && docker rm vicar-sidecar

# Re-enter directory to restart with new mounts
cd .. && cd -

# Or reload direnv
direnv reload
```

## Mount Points Inside Container

When configured, your data will be mounted at:

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `$CAMERA_MODELS_DIR` | `/vicar/config` | Camera models (.cahv, .cahvor files) |
| `$MISSION_DATA_DIR` | `/data/missions` | Mission data (images, EDRs) |
| `$POINT_FILES_DIR` | `/proj/mars/def` | Mars pointing files |
| `$WORKSPACE_ROOT` | `/workspace` | Your working directory |

## Common Use Cases

### Mounting Camera Models for Mars Processing

```bash
# In .envrc, add:
CAMERA_MODELS_DIR="/proj/mars/config"

# Container will have access to:
# /vicar/config/*.cahv
# /vicar/config/*.cahvor
# /vicar/config/m20/*.cahv
```

Then in your VICAR commands:

```bash
# Commands will automatically find camera models
marsmap input.img output.map CAHVOR=/vicar/config/m20/camera.cahvor
```

### Mounting Read-Only Mission Data

For large datasets you don't want to copy:

```bash
# In .envrc:
MISSION_DATA_DIR="/Volumes/MissionData/M2020/sols"

# Access in commands:
marsmos /data/missions/sol_00123/*.img output.mosaic
```

### Mounting Multiple Directories

You can add custom mounts by editing the `docker run` command in `.envrc`:

```bash
# Find the docker run command (around line 92-100) and add more volumes:
docker run -d \
    --name "${CONTAINER_NAME}" \
    ${net_args} \
    ${volume_args} \
    -v "/custom/data:/custom/data:ro" \
    -v "/scratch:/scratch" \
    ${x11_args} \
    -w /workspace \
    "${CONTAINER_IMAGE}" \
    tail -f /dev/null
```

## Mount Options

### Read-Only vs Read-Write

- **Read-only** (`:ro`): Prevents accidental modification of source data
- **Read-write** (default): Allows writing

```bash
-v "/source:/dest:ro"    # Read-only
-v "/source:/dest"       # Read-write
```

**Recommendation**: Mount calibration data and mission archives as read-only.

### Symbolic Links

If your data contains symbolic links, Docker will follow them if:

1. The symlink target is within the mounted volume
2. The symlink target is in another mounted volume
3. On macOS, symlink resolution may be slower due to VM layer

## Verification

### Check Mounted Volumes

```bash
# Enter container
toolkit-shell

# List mounted directories
ls -la /vicar/config
ls -la /data/missions
ls -la /proj/mars/def

# Verify camera models
find /vicar/config -name "*.cahv*" | head -10

# Exit
exit
```

### Test with VICAR Commands

```bash
# Test marsmap with camera model
cd workspace
marsmap input.img output.map

# Check if camera models are found
label output.map | grep CAHV
```

## Troubleshooting

### "Permission denied" Errors

On Linux, ensure your user has read access:

```bash
ls -la /path/to/camera/models
# Should show readable permissions
```

If needed, adjust permissions:

```bash
chmod -R a+rX /path/to/camera/models
```

### Mounts Not Visible in Container

1. Check if the directory exists on host:
   ```bash
   ls -la "${CAMERA_MODELS_DIR}"
   ```

2. Stop and remove container:
   ```bash
   docker stop vicar-sidecar && docker rm vicar-sidecar
   ```

3. Re-enter directory:
   ```bash
   cd .. && cd -
   ```

4. Verify mounts:
   ```bash
   docker inspect vicar-sidecar | grep Mounts -A 20
   ```

### macOS Performance Issues

Docker on macOS uses a VM layer, which can slow down file I/O:

**Solutions**:
- Enable VirtioFS in Docker Desktop (Settings → General → VirtioFS)
- For large datasets, copy frequently-used files to `workspace/` instead
- Use `:cached` or `:delegated` mount options for performance:
  ```bash
  -v "/data:/data:ro,cached"
  ```

### Camera Models Not Found by VICAR

VICAR looks for camera models in specific environment variables:

1. Check container environment:
   ```bash
   toolkit-shell
   env | grep -i config
   env | grep -i vicar
   ```

2. Set environment variables in `.envrc`:
   ```bash
   # After the docker run command, add:
   export V2CONFIG_PATH="/vicar/config"
   ```

3. Or pass to individual commands:
   ```bash
   docker exec -e V2CONFIG_PATH=/vicar/config vicar-sidecar marsmap ...
   ```

## Examples

### Example 1: Mount Local Camera Models

```bash
# Host structure:
# ~/mars/calibration/
#   ├── m20/
#   │   ├── zcam_left.cahvor
#   │   └── zcam_right.cahvor
#   └── msl/
#       └── mastcam.cahv

# In .envrc:
CAMERA_MODELS_DIR="${HOME}/mars/calibration"

# In container:
# /vicar/config/m20/zcam_left.cahvor
# /vicar/config/msl/mastcam.cahv
```

### Example 2: Mount JPL Network Paths

```bash
# On JPL network (Linux):
CAMERA_MODELS_DIR="/proj/mars/config"
MISSION_DATA_DIR="/proj/mars/m2020/data"
POINT_FILES_DIR="/proj/mars/def"

# Access in container:
marsmap /data/missions/sol_00001/*.img output.map
```

### Example 3: Mount S3 or Network Drives

```bash
# Mount network drive first (macOS):
# Finder → Go → Connect to Server → smb://server/share

# Then mount into container:
MISSION_DATA_DIR="/Volumes/MarsData"

# Or on Linux with CIFS:
# sudo mount -t cifs //server/share /mnt/mars

MISSION_DATA_DIR="/mnt/mars"
```

## Environment Variables

VICAR tools look for these environment variables:

| Variable | Purpose | Typical Value |
|----------|---------|---------------|
| `V2CONFIG_PATH` | Camera calibration files | `/vicar/config` |
| `V2TOP` | VICAR installation root | `/usr/local/vicar/dev` |
| `MARS_CONFIG_PATH` | Mars-specific config | `/vicar/config/mars` |
| `POINT_METHOD` | Pointing correction method | `SPICE` or `PLACES` |

Set these in the container by adding to `.envrc` after the `docker run` command:

```bash
# After container starts, export variables
docker exec vicar-sidecar bash -c "echo 'export V2CONFIG_PATH=/vicar/config' >> /etc/bashrc"
```

Or set them when running commands:

```bash
docker exec -e V2CONFIG_PATH=/vicar/config vicar-sidecar marsmap ...
```

## Advanced: Dynamic Mounts

For frequently changing data locations:

```bash
# In .envrc, add a function to prompt for paths:
_mount_custom_data() {
    read -p "Enter camera models path: " CAMERA_MODELS_DIR
    export CAMERA_MODELS_DIR
}

# Call before starting container
# _mount_custom_data
```

## Additional Resources

- [VICAR User Guide](https://www-mipl.jpl.nasa.gov/external/VICAR_guide.html)
- [Docker Volume Documentation](https://docs.docker.com/storage/volumes/)
- [Mars Processing Tools](https://github.jpl.nasa.gov/MIPL)

## Summary

1. Identify your data paths (camera models, mission data, etc.)
2. Edit `.envrc` to configure `CAMERA_MODELS_DIR`, `MISSION_DATA_DIR`, etc.
3. Uncomment the configuration lines
4. Restart the container: `docker stop vicar-sidecar && docker rm vicar-sidecar`
5. Re-enter directory: `cd .. && cd -`
6. Verify: `toolkit-shell` then `ls /vicar/config`

Your camera models are now accessible to all VICAR commands!
