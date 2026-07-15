# Mounting MARS Calibration Data

This guide explains how to mount MARS calibration files (camera models, flat fields, parameter files) into the VICAR Native Toolkit container.

## Quick Start

### 1. Set Environment Variable

Set `MARS_CONFIG_PATH` to point to your calibration directory:

```bash
# Add to shell profile (~/.bashrc or ~/.zshrc)
export MARS_CONFIG_PATH="${HOME}/.mars_calib"

# Or set temporarily
export MARS_CONFIG_PATH="/path/to/mars_calibration"
```

### 2. Restart Container

```bash
cd vicar-native-toolkit
toolkit-restart
```

### 3. Verify Calibration Mounted

```bash
toolkit-verify-calib
```

Expected output:
```
=== MARS Calibration Verification ===
MARS_CONFIG_PATH: /usr/local/vicar/mars_calib

Mount point exists: /usr/local/vicar/mars_calib
Contents:
drwxr-xr-x camera_models
drwxr-xr-x flat_fields
drwxr-xr-x param_files

Camera models: 226
Flat fields: 381
Param files: 3
```

## Configuration Options

### Option 1: Shell Environment Variable (Recommended)

Set in your shell profile for persistent configuration:

```bash
# ~/.bashrc or ~/.zshrc
export MARS_CONFIG_PATH="${HOME}/.mars_calib"
```

Then activate the toolkit:

```bash
cd vicar-native-toolkit
direnv allow
```

### Option 2: Local Configuration File

Copy and edit the configuration file:

```bash
cd vicar-native-toolkit
cp .envrc.config.example .envrc.config
```

Edit `.envrc.config`:

```bash
# Uncomment and set your path
MARS_CONFIG_PATH="${HOME}/.mars_calib"
```

Then activate:

```bash
direnv allow
```

### Option 3: Temporary Override

Set for current shell session only:

```bash
export MARS_CONFIG_PATH="/tmp/test_calibration"
cd vicar-native-toolkit
direnv allow
```

## Calibration Directory Structure

Your calibration directory should contain:

```
mars_calibration/
├── camera_models/
│   ├── *.cahvor     # Camera geometry files
│   └── *.cahvore    # Extended camera models
├── flat_fields/
│   └── *.IMG        # Radiometric correction data
└── param_files/
    └── *.xml        # Camera mapping configuration
```

MARS tools (marsmap, marsmos, marsmesh) automatically discover files from these subdirectories using the `$MARS_CONFIG_PATH` environment variable.

## Mount Behavior

### When MARS_CONFIG_PATH is Set and Valid

```bash
export MARS_CONFIG_PATH="/opt/mars_calibration"
```

**Result:**
- Host path: `/opt/mars_calibration`
- Container path: `/usr/local/vicar/mars_calib` (read-only)
- Container environment: `MARS_CONFIG_PATH=/usr/local/vicar/mars_calib`
- Log: `[vicar-toolkit] Mounting MARS calibration: /opt/mars_calibration`

### When MARS_CONFIG_PATH is Set but Directory Missing

```bash
export MARS_CONFIG_PATH="/nonexistent/path"
```

**Result:**
- Mount skipped
- Container starts successfully
- Log: `[vicar-toolkit] MARS_CONFIG_PATH set but directory not found: /nonexistent/path (skipping)`
- MARS tools will fail if they require camera models

### When MARS_CONFIG_PATH is Not Set

```bash
# unset MARS_CONFIG_PATH
```

**Result:**
- Mount skipped silently
- Container starts normally
- No calibration available
- Valid configuration for non-MARS workflows

## Mount Details

### Container Mount Point

| Host Path | Container Path | Mount Options |
|-----------|----------------|---------------|
| `$MARS_CONFIG_PATH` | `/usr/local/vicar/mars_calib` | `ro,Z` (read-only, SELinux-safe) |

### Environment Variable

Inside the container, `MARS_CONFIG_PATH` is set to `/usr/local/vicar/mars_calib` automatically when calibration is mounted.

MARS tools check this variable to locate:
- Camera geometry files (`.cahvor`, `.cahvore`)
- Radiometric correction data (flat field `.IMG` files)
- Camera mapping XML files

### Mount Options

- **Read-only (`:ro`)**: Prevents accidental modification of calibration files
- **SELinux-safe (`:Z`)**: Relabels files for container access on SELinux systems (Linux)
- The `:Z` flag is safe on macOS and will be ignored if not needed

## Configuration Examples

### Example 1: TIG Repository Structure

If you have the terrain-intelligence-generator repository cloned as a sibling:

```bash
# In .envrc.config
MARS_CONFIG_PATH="${PWD}/../terrain-intelligence-generator/docker/mars_calibration"
```

### Example 2: User Home Directory

Store calibration in your home directory:

```bash
# In ~/.bashrc
export MARS_CONFIG_PATH="${HOME}/.mars_calib"

# Download/copy calibration files
mkdir -p ~/.mars_calib
# ... copy camera_models/, flat_fields/, param_files/ ...
```

### Example 3: System-Wide Installation

For shared systems with calibration in `/opt`:

```bash
# In .envrc.config
MARS_CONFIG_PATH="/opt/mars_calibration"
```

### Example 4: Per-Mission Calibration

Switch between missions using different paths:

```bash
# Mission A
export MARS_CONFIG_PATH="/data/mars/mission-a/calibration"

# Mission B
export MARS_CONFIG_PATH="/data/mars/mission-b/calibration"
```

## Verification

### Using toolkit-verify-calib

The built-in verification function checks calibration mount status:

```bash
toolkit-verify-calib
```

Output shows:
1. Whether `MARS_CONFIG_PATH` is set
2. Whether mount point exists
3. Directory contents
4. Count of camera models, flat fields, parameter files

### Manual Verification

Enter container shell:

```bash
toolkit-shell
```

Check environment and files:

```bash
# Check environment variable
echo $MARS_CONFIG_PATH

# List calibration directory
ls -lh /usr/local/vicar/mars_calib/

# Count camera models
find /usr/local/vicar/mars_calib/camera_models -name "*.cahv*" | wc -l

# Exit container
exit
```

### Test with MARS Tools

Run a MARS command that requires calibration:

```bash
cd workspace
marsmap input.img output.map

# If calibration is correct, marsmap will find camera models automatically
```

## Troubleshooting

### "Directory not found" Warning

**Symptom:**
```
[vicar-toolkit] MARS_CONFIG_PATH set but directory not found: /bad/path (skipping)
```

**Solution:**
1. Verify path exists: `ls -la /bad/path`
2. Fix typo in path
3. Create directory if needed: `mkdir -p /correct/path`
4. Restart container: `toolkit-restart`

### "Permission denied" Error

**Symptom:**
```
docker: Error response from daemon: error while creating mount source path: permission denied
```

**Solution:**
Ensure your user has read access to the calibration directory:

```bash
# Check permissions
ls -la /path/to/calibration

# Fix if needed (Linux)
chmod -R a+rX /path/to/calibration
```

### Empty Calibration Directory

**Symptom:**
```
Camera models: 0
Flat fields: 0
Param files: 0
```

**Solution:**
1. Verify host directory contains files: `ls -R $MARS_CONFIG_PATH`
2. Ensure subdirectories exist: `camera_models/`, `flat_fields/`, `param_files/`
3. Copy calibration files to correct subdirectories

### MARS Tools Can't Find Camera Models

**Symptom:**
```
[marsmap] Error: Unable to locate camera model file
```

**Solution:**
1. Run `toolkit-verify-calib` to check mount status
2. Verify `MARS_CONFIG_PATH` is set in container:
   ```bash
   docker exec vicar-sidecar bash -c 'echo $MARS_CONFIG_PATH'
   ```
3. Check file naming conventions (tools expect specific patterns)
4. Verify files are in `camera_models/` subdirectory

### Mount Not Visible After Configuration

**Solution:**
1. Container must be recreated for mount changes to take effect
2. Stop container: `toolkit-stop`
3. Re-enter directory: `cd .. && cd vicar-native-toolkit`
4. Or use: `toolkit-restart` (requires re-entering directory)

### macOS Specific Issues

On macOS, Docker uses a VM layer:

**Slow performance:**
- Enable VirtioFS in Docker Desktop (Settings → General → VirtioFS)
- For frequently-accessed files, consider copying to `workspace/` instead

**Symlink issues:**
- Ensure symlink targets are within mounted volume
- Absolute symlinks may not resolve correctly

## Platform Differences

### Linux
- SELinux systems (Fedora, RHEL, CentOS) require `:Z` flag (already included)
- Direct filesystem access (faster than macOS)
- May need permission adjustments for shared directories

### macOS
- Uses Docker Desktop VM
- `:Z` flag is safely ignored
- VirtioFS recommended for better performance
- Network mounts (SMB, NFS) work but may be slower

## Advanced: docker-compose.yml Configuration

For docker-compose users, add calibration mount:

```yaml
volumes:
  - ./workspace:/workspace:Z
  - ${MARS_CONFIG_PATH}:/usr/local/vicar/mars_calib:ro,Z

environment:
  - MARS_CONFIG_PATH=/usr/local/vicar/mars_calib
```

Uncomment and customize for your setup.

## Summary

1. **Set `MARS_CONFIG_PATH`** environment variable to your calibration directory
2. **Restart container** with `toolkit-restart`
3. **Verify** with `toolkit-verify-calib`
4. **Use MARS tools** - they will automatically find calibration files

**Key points:**
- Configuration is explicit - no auto-detection
- Mount is read-only to protect source files
- Container must be recreated for mount changes
- Works identically on Linux and macOS
- Non-MARS workflows work fine without calibration
