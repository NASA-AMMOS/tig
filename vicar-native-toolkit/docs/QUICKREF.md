# Quick Reference: VICAR Native Toolkit

## Automated Setup (Fastest)

```bash
# Clone repository
git clone https://github.com/NASA-AMMOS/tig.git
cd tig/vicar-native-toolkit

# One-command bootstrap
./bootstrap.sh

# That's it! VICAR commands now available
gen out=test.img nl=10 ns=10
toolkit-status
```

**With MARS calibration:**
```bash
./bootstrap.sh --mars-calib /path/to/mars_calibration_m20
```

**Custom image:**
```bash
./bootstrap.sh --image myregistry/vicar:custom
```

See `./bootstrap.sh --help` for all options.

## Pull & Run (Docker Only)

```bash
# Pull latest open-source build
docker pull ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource

# Run with workspace
docker run -it --rm \
  -v $(pwd)/data:/workspace \
  ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource \
  bash
```

## Native Toolkit Commands

Once activated via bootstrap or direnv:

```bash
# Utility commands
toolkit-status         # Show container status
toolkit-shell          # Interactive shell in container
toolkit-stop           # Stop and remove container
toolkit-restart        # Restart container
toolkit-verify-calib   # Verify MARS calibration (if configured)

# VICAR commands work natively
gen output.vic 512 512
label image.vic
marsmap input.img output.map
```

## Common Commands

```bash
# Generate test image
gen output.vic 512 512

# Display label information
label image.vic

# List image contents
list image.vic

# Convert VICAR to PNG/JPEG/TIFF
vicario image.vic image.png
vicario image.vic image.jpg

# MARS terrain processing
marsmap input.img output.map
marsmos *.img output.mosaic
```

## Build Locally

```bash
cd vicar-native-toolkit
./scripts/build-opensource-image.sh
```

## X11 Apps (Linux)

```bash
xhost +local:docker

docker run -it --rm \
  -v $(pwd)/data:/workspace \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -e DISPLAY=$DISPLAY \
  --network host \
  ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource \
  bash

# Inside container, run GUI apps
xvd image.vic
```

## X11 Apps (macOS)

```bash
# Start XQuartz first
open -a XQuartz
xhost +localhost

docker run -it --rm \
  -v $(pwd)/data:/workspace \
  -e DISPLAY=host.docker.internal:0 \
  ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource \
  bash
```

## Environment Check

```bash
# Inside container
echo $V2TOP                    # /usr/local/vicar/vos
echo $LD_LIBRARY_PATH          # VICAR library paths
ls /usr/local/bin | head -20   # Available wrappers
which label                    # /usr/local/bin/label
```

## Configuration

```bash
# View current config
cat .envrc.local

# Reconfigure
./bootstrap.sh --config-only --image new-image:tag

# Reload configuration
direnv allow
toolkit-restart
```

## Architecture

The native toolkit uses a **symlink-based wrapper** approach:
- Single `vicar-exec` script handles all commands
- ~550 symlinks created dynamically
- Fast activation (~1 second)
- Low disk usage (~2MB)
- Commands auto-discovered from container

## Troubleshooting

```bash
# Toolkit not activating
direnv allow
cd .. && cd -

# Container not running
toolkit-restart

# Commands not found
echo $PATH | grep .direnv
ls .direnv/wrappers/ | wc -l   # Should show ~550

# Check wrapper implementation
file .direnv/wrappers/gen      # Should be symlink
readlink .direnv/wrappers/gen  # Should point to ../vicar-exec

# Image issues
docker images | grep terrain-intelligence-generator
docker pull ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource

# Container logs
docker logs vicar-sidecar

# Fresh start
toolkit-stop
rm -rf .direnv/
direnv allow
```

## Links

- **Documentation**: [OPENSOURCE-BUILD.md](OPENSOURCE-BUILD.md)
- **VICAR Source**: https://github.com/NASA-AMMOS/VICAR
- **TIG Repository**: https://github.com/NASA-AMMOS/tig
- **Container Registry**: https://github.com/orgs/NASA-AMMOS/packages
