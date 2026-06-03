# MARS Calibration Mounting for vicar-native-toolkit

**Date:** 2026-06-03  
**Status:** Approved  
**Component:** vicar-native-toolkit

## Overview

Add support for mounting MARS calibration files (camera models, flat fields, parameter files) into the vicar-native-toolkit container using the `MARS_CONFIG_PATH` environment variable. This aligns with the terrain-intelligence-generator Docker image conventions and enables MARS processing tools to automatically discover calibration data.

## Background

The terrain-intelligence-generator Docker image expects MARS calibration data to be:
- Mounted at runtime at `/usr/local/vicar/mars_calib` (read-only)
- Accessed via `MARS_CONFIG_PATH=/usr/local/vicar/mars_calib` environment variable
- Structured with subdirectories: `camera_models/`, `flat_fields/`, `param_files/`

MARS tools (marsmap, marsmos, marsmesh, etc.) use `$MARS_CONFIG_PATH` to discover:
- Camera geometry files (`.cahvor`, `.cahvore`)
- Radiometric correction data (flat field `.IMG` files)
- Camera mapping XML files

Currently, vicar-native-toolkit documentation references calibration mounting, but implementation is incomplete and uses inconsistent variable names (`CAMERA_MODELS_DIR` vs `MARS_CONFIG_PATH`).

## Goals

1. **Align with terrain-intelligence-generator conventions** - Use `MARS_CONFIG_PATH` as the standard environment variable
2. **Support explicit configuration** - Users set environment variable or configure in `.envrc.config`
3. **Fail gracefully** - Skip calibration mount if not configured; warn if path invalid
4. **Provide verification tools** - Users can confirm calibration mounted correctly

## Design

### Configuration Sources (Priority Order)

1. **Environment variable:** `export MARS_CONFIG_PATH=/path/to/calibration`
2. **`.envrc.config` file:** `MARS_CONFIG_PATH="${HOME}/.mars_calib"`
3. **Not configured:** Skip calibration mount (valid use case)

### Mount Behavior

**When `MARS_CONFIG_PATH` is set and valid:**
- Host path: Value of `$MARS_CONFIG_PATH`
- Container path: `/usr/local/vicar/mars_calib`
- Mount options: Read-only (`:ro`), SELinux-safe (`:Z`)
- Container environment: `MARS_CONFIG_PATH=/usr/local/vicar/mars_calib`
- Logging: `[vicar-toolkit] Mounting MARS calibration: /host/path`

**When `MARS_CONFIG_PATH` is set but directory missing:**
- Skip mount
- Log warning: `[vicar-toolkit] MARS_CONFIG_PATH set but directory not found: /path (skipping)`
- Continue container startup without calibration

**When `MARS_CONFIG_PATH` is unset or empty:**
- Skip mount silently
- No calibration available in container
- Valid configuration for non-MARS workflows

### Implementation Changes

#### 1. `.envrc` Script Modifications

**Add volume argument building (after line ~50):**
```bash
# Build volume arguments
volume_args="-v ${WORKSPACE_ROOT}:/workspace:Z"

# Add MARS calibration mount if configured
if [[ -n "${MARS_CONFIG_PATH}" ]]; then
    if [[ -d "${MARS_CONFIG_PATH}" ]]; then
        volume_args="${volume_args} -v ${MARS_CONFIG_PATH}:/usr/local/vicar/mars_calib:ro,Z"
        log_info "Mounting MARS calibration: ${MARS_CONFIG_PATH}"
    else
        log_info "MARS_CONFIG_PATH set but directory not found: ${MARS_CONFIG_PATH} (skipping)"
    fi
fi
```

**Update Docker run command (around line 70):**
```bash
DOCKER_ARGS=(
    "-d"
    "--name" "${CONTAINER_NAME}"
    ${volume_args}  # Use computed volume arguments
    "-w" "/workspace"
)

# Add environment variables
if [[ -n "${MARS_CONFIG_PATH}" ]] && [[ -d "${MARS_CONFIG_PATH}" ]]; then
    DOCKER_ARGS+=("-e" "MARS_CONFIG_PATH=/usr/local/vicar/mars_calib")
fi
```

**Add verification utility function (before final exports):**
```bash
toolkit-verify-calib() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_error "Container not running"
        return 1
    fi
    
    echo "=== MARS Calibration Verification ==="
    docker exec "${CONTAINER_NAME}" bash -c '
        echo "MARS_CONFIG_PATH: ${MARS_CONFIG_PATH:-not set}"
        echo ""
        if [[ -n "${MARS_CONFIG_PATH}" ]]; then
            if [[ -d "${MARS_CONFIG_PATH}" ]]; then
                echo "Mount point exists: ${MARS_CONFIG_PATH}"
                echo "Contents:"
                ls -lh ${MARS_CONFIG_PATH}
                echo ""
                echo "Camera models: $(find ${MARS_CONFIG_PATH}/camera_models -name "*.cahv*" 2>/dev/null | wc -l)"
                echo "Flat fields: $(find ${MARS_CONFIG_PATH}/flat_fields -name "*.IMG" 2>/dev/null | wc -l)"
                echo "Param files: $(find ${MARS_CONFIG_PATH}/param_files -name "*.xml" 2>/dev/null | wc -l)"
            else
                echo "ERROR: MARS_CONFIG_PATH set but directory not found"
            fi
        else
            echo "Calibration not configured (MARS_CONFIG_PATH not set)"
        fi
    '
}

export -f toolkit-verify-calib
```

#### 2. `.envrc.config.example` Updates

**Add configuration section (after line 62):**
```bash
# ===== MARS Calibration (Camera Models & Flat Fields) =====
# Uncomment and set to mount M2020 calibration data
# This should point to a directory containing:
#   - camera_models/ (*.cahvor, *.cahvore files)
#   - flat_fields/ (*.IMG radiometric correction files)
#   - param_files/ (*.xml camera mapping files)
#
# Examples:
# MARS_CONFIG_PATH="${HOME}/.mars_calib"
# MARS_CONFIG_PATH="/opt/mars_calibration_m20"
# MARS_CONFIG_PATH="${PWD}/../terrain-intelligence-generator/docker/mars_calibration_m20"
#
# If not set, container will start without calibration data.
# MARS tools will fail if they require camera models.
```

**Remove obsolete `CAMERA_MODELS_DIR` references (lines 69-82):**
Delete the old auto-detection section that references `CAMERA_MODELS_DIR` and `CAMERA_MODELS_MOUNT`.

#### 3. `MOUNTING-DATA.md` Rewrite

**Simplify to focus on `MARS_CONFIG_PATH`:**

- Replace "Camera Models and External Data" with "MARS Calibration Data"
- Update all examples to use `MARS_CONFIG_PATH` instead of `CAMERA_MODELS_DIR`
- Remove `V2CONFIG_PATH` references (not used by terrain-intelligence-generator)
- Update mount table to show `/usr/local/vicar/mars_calib` as container path
- Simplify verification steps to use `toolkit-verify-calib`
- Update environment variables table to focus on `MARS_CONFIG_PATH`
- Remove legacy `POINT_FILES_DIR` and `MISSION_DATA_DIR` (not in scope)

**Key sections to preserve:**
- Quick Start flow (set variable → restart container → verify)
- Mount options explanation (read-only, SELinux)
- Troubleshooting (permissions, path validation)
- Examples for different host configurations

#### 4. `docker-compose.yml` Updates

**Add commented calibration mount example (line 21):**
```yaml
volumes:
  - ./workspace:/workspace:Z
  # MARS calibration (uncomment and customize)
  # - ${MARS_CONFIG_PATH}:/usr/local/vicar/mars_calib:ro,Z
```

**Add environment variable (line 17):**
```yaml
environment:
  - WORKSPACE=/usr/local/vicar
  - VICSYS=DEVELOPMENT
  # - MARS_CONFIG_PATH=/usr/local/vicar/mars_calib  # Uncomment if mounting calibration
```

### User Workflows

#### Workflow 1: Shell Environment Variable

```bash
# Set in shell profile (~/.bashrc or ~/.zshrc)
export MARS_CONFIG_PATH="${HOME}/.mars_calib"

# Download/place calibration files
mkdir -p ~/.mars_calib
# ... copy camera_models/, flat_fields/, param_files/ ...

# Activate toolkit
cd vicar-native-toolkit
direnv allow

# Verify
toolkit-verify-calib

# Use MARS tools
marsmap input.img output.map
```

#### Workflow 2: Local Configuration File

```bash
# Copy example config
cd vicar-native-toolkit
cp .envrc.config.example .envrc.config

# Edit .envrc.config
MARS_CONFIG_PATH="${PWD}/../terrain-intelligence-generator/docker/mars_calibration_m20"

# Activate toolkit
direnv allow

# Verify
toolkit-verify-calib
```

#### Workflow 3: No Calibration (Skip)

```bash
# Don't set MARS_CONFIG_PATH
cd vicar-native-toolkit
direnv allow

# Container starts without calibration
# MARS tools will fail if they need camera models
# Non-MARS VICAR tools work fine
```

### Error Handling

**Scenario: Path set but directory missing**
```
[vicar-toolkit] MARS_CONFIG_PATH set but directory not found: /bad/path (skipping)
[vicar-toolkit] Creating new container 'vicar-sidecar'...
[vicar-toolkit] Container started successfully
```
Result: Container starts, no calibration mounted

**Scenario: Path exists but no read permissions**
```
docker: Error response from daemon: error while creating mount source path '/path/to/calib': permission denied.
```
Result: Docker fails before container starts - user sees error

**Scenario: Path exists but empty**
```
[vicar-toolkit] Mounting MARS calibration: /path/to/empty
[vicar-toolkit] Container started successfully
```
Result: Container starts, mount exists but tools won't find files

**Verification catches issues:**
```bash
$ toolkit-verify-calib
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

### Testing Plan

**Test 1: Valid configuration**
- Set `MARS_CONFIG_PATH` to existing directory with calibration
- Start container
- Verify mount with `toolkit-verify-calib`
- Run `marsmap` with input image
- Confirm camera model loaded from `/usr/local/vicar/mars_calib`

**Test 2: Path not set**
- Unset `MARS_CONFIG_PATH`
- Start container
- Confirm no mount added
- Confirm no warning logged
- `toolkit-verify-calib` shows "not configured"

**Test 3: Path set but missing**
- Set `MARS_CONFIG_PATH` to non-existent path
- Start container
- Confirm warning logged
- Confirm container starts successfully
- Confirm no mount added

**Test 4: Empty calibration directory**
- Set `MARS_CONFIG_PATH` to empty directory
- Start container
- Confirm mount added
- `toolkit-verify-calib` shows 0 files
- MARS tools fail with "camera model not found"

**Test 5: Cross-platform (Linux/macOS)**
- Test on both platforms
- Confirm `:Z` flag doesn't break macOS
- Confirm read-only mount works

### Documentation Updates

**Files to update:**
1. ✅ `.envrc` - Add mounting logic and verification function
2. ✅ `.envrc.config.example` - Document `MARS_CONFIG_PATH` configuration
3. ✅ `MOUNTING-DATA.md` - Rewrite to focus on `MARS_CONFIG_PATH`
4. ✅ `docker-compose.yml` - Add commented calibration mount example
5. `README.md` - Add quick reference to calibration mounting (brief section)

**README.md addition (after "Using External Data" section ~line 212):**
```markdown
### Mounting Calibration Data

For MARS processing tools (marsmap, marsmos, etc.), mount calibration files:

```bash
# Set environment variable
export MARS_CONFIG_PATH="/path/to/mars_calibration_m20"

# Restart container
cd vicar-native-toolkit
toolkit-restart

# Verify calibration mounted
toolkit-verify-calib
```

See [MOUNTING-DATA.md](MOUNTING-DATA.md) for detailed configuration options.
```

## Dependencies

**Requires:**
- vicar-native-toolkit with `.envrc` direnv activation
- Docker with volume mount support
- terrain-intelligence-generator Docker image (any version)

**Does not require:**
- Changes to Docker image
- Changes to VICAR/MARS tools
- Network access
- Specific directory structure on host (user's choice)

## Security Considerations

- **Read-only mount:** Prevents accidental modification of calibration source files
- **SELinux safe:** `:Z` flag relabels files for container access on SELinux systems
- **No secrets:** Calibration files are non-sensitive scientific data
- **Path validation:** Checks directory exists before mounting

## Future Enhancements (Out of Scope)

1. **Auto-download calibration:** Script to fetch calibration from repository
2. **Multiple calibration sets:** Support MSL, M2020, PHX via separate variables
3. **Calibration versioning:** Track which calibration version mounted
4. **Smart path detection:** Search common locations if `MARS_CONFIG_PATH` unset

These are explicitly excluded from this design to maintain simplicity and explicit configuration.

## Success Criteria

1. User sets `MARS_CONFIG_PATH` and calibration mounts automatically
2. MARS tools find camera models without additional configuration
3. Clear error messages if path invalid
4. Works identically on Linux and macOS
5. Backward compatible - existing workflows without calibration still work
6. Documentation clearly explains setup steps

## Summary

This design adds MARS calibration mounting to vicar-native-toolkit through explicit configuration of the `MARS_CONFIG_PATH` environment variable. It aligns with terrain-intelligence-generator image conventions, provides clear feedback, and fails gracefully when misconfigured. Implementation requires modifications to `.envrc`, `.envrc.config.example`, `MOUNTING-DATA.md`, and `docker-compose.yml`.
