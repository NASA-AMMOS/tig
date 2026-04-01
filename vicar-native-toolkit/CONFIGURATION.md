# VICAR Native Toolkit - Configuration Guide

## Overview

The VICAR Native Toolkit now supports **configurable VICAR images**, allowing you to use any VICAR build including:
- **RPM-based builds** (M20-G87, etc.)
- **Source-built images** (development)
- **Custom images** with specific configurations

## Quick Start

### 1. Choose Your Configuration

Copy the example configuration and customize it:

```bash
cp .envrc.config.example .envrc.local
# Edit .envrc.local for your setup
```

### 2. Configure for Your Image

The toolkit includes a default configuration for `vicar-tools:tig-demo` (M20-G87 RPM build). To use a different image, edit `.envrc.local`:

```bash
# Change the image
CONTAINER_IMAGE="your-image:tag"

# Update paths to match your image's VICAR installation
VICAR_INSTALL_PREFIX="/usr/local/vicar/your-build"
VICAR_BIN_PATHS=(
    "/usr/local/bin"
    "${VICAR_INSTALL_PREFIX}/p2/lib/x86-64-linx"
)
```

### 3. Activate

```bash
direnv allow
# Container starts, wrappers generate, commands work natively!
```

## Configuration Files

### Priority Order

1. **`.envrc.local`** (gitignored) - Your personal configuration
2. **`.envrc.config`** (tracked) - Project default configuration  
3. **`.envrc.config.example`** - Template with all options

### File Purposes

| File | Purpose | Tracked |
|------|---------|---------|
| `.envrc` | Main activation script (don't edit) | ✅ Yes |
| `.envrc.config` | Project default (M20-G87) | ✅ Yes |
| `.envrc.config.example` | Template with all options | ✅ Yes |
| `.envrc.local` | Your personal overrides | ❌ No (gitignored) |

## Configuration Options

### Container Settings

```bash
# Container name (must be unique per instance)
CONTAINER_NAME="vicar-sidecar"

# Docker image to use
CONTAINER_IMAGE="vicar-tools:tig-demo"
```

### VICAR Paths

Configure paths **inside the container** where VICAR is installed:

```bash
# Base installation directory
VICAR_INSTALL_PREFIX="/usr/local/vicar/m20-g87"

# Executable search paths (array)
VICAR_BIN_PATHS=(
    "/usr/local/bin"                                    # System commands
    "${VICAR_INSTALL_PREFIX}/p2/lib/x86-64-linx"       # VICAR core
    "${VICAR_INSTALL_PREFIX}/mars/lib/x86-64-linx"     # Mars tools
)

# Library paths (array)
VICAR_LIB_PATHS=(
    "${VICAR_INSTALL_PREFIX}/olb/x86-64-linx"
    "${VICAR_INSTALL_PREFIX}/mars/lib/x86-64-linx"
)
```

### Environment Variables

Set environment variables that VICAR tools need:

```bash
VICAR_ENV_VARS=(
    "V2TOP=${VICAR_INSTALL_PREFIX}"
    "R2LIB=${VICAR_INSTALL_PREFIX}"
    "VICAR_PARAM=/projects/project/calibration/param_files"
    "VICAR_CALIB=/projects/project/calibration"
)
```

### Additional Mounts

Mount external directories into the container:

```bash
# Mount parent directory for sibling projects
PARENT_DIR="$(dirname ${PWD})"
PARENT_MOUNT="/projects"

# Mount calibration data
CAMERA_MODELS_DIR="/path/to/calibration"
CAMERA_MODELS_MOUNT="/project"
```

### Wrapper Generation

```bash
# Auto-discover all executables (recommended)
AUTO_DISCOVER_TOOLS=true

# Or manually specify tools
AUTO_DISCOVER_TOOLS=false
MANUAL_TOOLS=(
    label hist gen size list
    marscorr marsxyz marsmap
)
```

## Example Configurations

### M20-G87 RPM Build (Default)

```bash
CONTAINER_IMAGE="vicar-tools:tig-demo"
VICAR_INSTALL_PREFIX="/usr/local/vicar/m20-g87"
VICAR_BIN_PATHS=(
    "/usr/local/bin"
    "${VICAR_INSTALL_PREFIX}/p2/lib/x86-64-linx"
    "${VICAR_INSTALL_PREFIX}/mars/lib/x86-64-linx"
)
AUTO_DISCOVER_TOOLS=true
```

### Source-Built Development Image

```bash
CONTAINER_IMAGE="vicar-tools:local-binaries"
VICAR_INSTALL_PREFIX="/usr/local/vicar/dev"
VICAR_BIN_PATHS=(
    "${VICAR_INSTALL_PREFIX}/p1/lib/x86-64-linx"
    "${VICAR_INSTALL_PREFIX}/p2/lib/x86-64-linx"
    "${VICAR_INSTALL_PREFIX}/p3/lib/x86-64-linx"
    "${VICAR_INSTALL_PREFIX}/mars/lib/x86-64-linx"
)
AUTO_DISCOVER_TOOLS=true
```

### Minimal Configuration

```bash
CONTAINER_IMAGE="my-vicar:latest"
VICAR_BIN_PATHS=("/usr/local/bin")
AUTO_DISCOVER_TOOLS=true
```

## Usage

### Activation

```bash
cd vicar-native-toolkit
direnv allow
# ✅ Container starts with your configured image
# ✅ Wrappers generated for all commands
# ✅ Commands work natively!
```

### Using Commands

```bash
# All commands work like native CLI tools
gen out=test.vic nl=512 ns=512
hist inp=test.vic
label -list test.vic

# Mars commands work too
marscorr inp=(left.vic,right.vic) out=disp.vic
marsxyz inp=disp.vic out=xyz.vic
```

### Management Commands

```bash
toolkit-status    # Show configuration and status
toolkit-shell     # Open container shell
toolkit-restart   # Restart with new config
toolkit-stop      # Stop and remove container
```

## Switching Between Images

### Method 1: Edit Configuration

```bash
# Edit your .envrc.local
vim .envrc.local
# Change CONTAINER_IMAGE="new-image:tag"

# Restart
toolkit-restart
cd .. && cd -
```

### Method 2: Multiple Configurations

```bash
# Save current config
cp .envrc.local .envrc.local.m20-g87

# Load different config
cp .envrc.local.dev .envrc.local

# Restart
toolkit-restart
cd .. && cd -
```

## Troubleshooting

### "Configuration file not found"

**Solution:** Create a configuration file:
```bash
cp .envrc.config.example .envrc.local
# Edit .envrc.local
direnv allow
```

### "Image not found"

**Solution:** Build or pull the image:
```bash
docker pull your-image:tag
# Or build it
./scripts/build-tig-demo-image.sh
```

### "Commands not found"

**Solution:** Check wrapper generation:
```bash
toolkit-status  # Shows number of wrappers
ls .direnv/wrappers/ | wc -l
```

If wrappers aren't generated:
```bash
# Regenerate wrappers
toolkit-restart
cd .. && cd -
```

### "Wrong paths in container"

**Solution:** Update configuration paths:
```bash
# Check what's actually in the container
toolkit-shell
ls /usr/local/vicar/
ls /usr/local/bin/

# Update .envrc.local with correct paths
```

## Advanced Usage

### Custom Environment Variables

```bash
VICAR_ENV_VARS=(
    "V2TOP=/usr/local/vicar/m20-g87"
    "R2LIB=/usr/local/vicar/m20-g87"
    "CUSTOM_VAR=value"
    "PATH=/custom/path:\$PATH"
)
```

### Multiple Mount Points

```bash
# Mount multiple directories
PARENT_DIR="$(dirname ${PWD})"
PARENT_MOUNT="/projects"

CAMERA_MODELS_DIR="/data/calibration"
CAMERA_MODELS_MOUNT="/calib"

MISSION_DATA_DIR="/data/missions"
MISSION_DATA_MOUNT="/missions"
```

### Platform-Specific Configuration

```bash
HOST_OS="$(uname -s)"

if [[ "$HOST_OS" == "Darwin" ]]; then
    # macOS-specific settings
    CONTAINER_NAME="vicar-mac"
else
    # Linux-specific settings
    CONTAINER_NAME="vicar-linux"
fi
```

## Migration Guide

### From Old .envrc (Pre-Configurable)

Old (hardcoded):
```bash
CONTAINER_IMAGE="vicar-tools:with-rpms"
# Paths hardcoded in script
```

New (configurable):
```bash
# Create .envrc.local
cp .envrc.config.example .envrc.local

# Set your image
CONTAINER_IMAGE="vicar-tools:with-rpms"

# Configure paths for your image
VICAR_INSTALL_PREFIX="/usr/local/vicar/dev"
VICAR_BIN_PATHS=(...)
```

## Best Practices

1. ✅ **Use .envrc.local for personal config** - Not tracked in git
2. ✅ **Keep .envrc.config as project default** - Tracked, documented
3. ✅ **Document custom configurations** - Add comments in .envrc.local
4. ✅ **Test after configuration changes** - Run `toolkit-status`
5. ✅ **Use AUTO_DISCOVER_TOOLS=true** - Finds all commands automatically

## Reference

### Default Paths by Image

| Image | Prefix | Commands Location |
|-------|--------|-------------------|
| `vicar-tools:tig-demo` | `/usr/local/vicar/m20-g87` | `/usr/local/bin` + `$PREFIX/p2/lib/...` |
| `vicar-tools:with-rpms` | `/usr/local/vicar/m20-g87` | `/usr/local/bin` + `$PREFIX/p2/lib/...` |
| `vicar-tools:local-binaries` | `/usr/local/vicar/dev` | `$PREFIX/p2/lib/x86-64-linx` |

### Common Environment Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `V2TOP` | VICAR installation root | `/usr/local/vicar/m20-g87` |
| `R2LIB` | Mars tools library | Same as V2TOP |
| `VICAR_PARAM` | Parameter files | `/project/calibration/param_files` |
| `VICAR_CALIB` | Calibration data | `/project/calibration` |

---

**Now the toolkit works with ANY VICAR image!** 🚀

Just configure paths and environment variables to match your image's layout.
