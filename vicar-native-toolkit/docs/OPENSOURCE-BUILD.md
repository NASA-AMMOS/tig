# VICAR Native Toolkit - Open Source Build

This directory contains the open-source build of the VICAR Native Toolkit, which builds VICAR from the public GitHub repository without requiring access to JPL internal resources.

## Quick Start

### Using Pre-built Image from GitHub Container Registry

The easiest way to get started is to use the pre-built image:

```bash
# Pull the latest open-source build
docker pull ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource

# Run interactively
docker run -it --rm \
  -v $(pwd)/workspace:/workspace \
  ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource \
  bash

# Test VICAR commands
docker run --rm ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource label --help
```

### Building Locally

If you want to build the image yourself:

```bash
# Build with default settings (latest VICAR main branch)
./scripts/build-opensource-image.sh

# Build with specific VICAR version
VICAR_VERSION=v3.0 ./scripts/build-opensource-image.sh

# Build with custom image name
IMAGE_NAME=my-vicar IMAGE_TAG=latest ./scripts/build-opensource-image.sh
```

Build time: 30-60 minutes depending on your system.

## What's Included

The open-source build includes:

- **VICAR** - Video Image Communication and Retrieval system
  - Core image processing tools (p2 programs)
  - TAE (Terminal Application Executive) 
  - MARS terrain processing tools
  - Supporting libraries (olb)
  
- **Runtime Environment**
  - Rocky Linux 8 (RHEL-compatible)
  - Python 3.9
  - X11 libraries for GUI applications
  - Java 8 runtime
  - Image processing libraries (libtiff, libpng, libjpeg)

- **Wrapper Scripts**
  - ~200+ command-line wrappers in `/usr/local/bin`
  - Automatic environment setup
  - Pre-configured library paths

## Architecture

The build uses a multi-stage Dockerfile:

1. **Builder Stage** (`rockylinux:8`)
   - Installs all build dependencies
   - Clones VICAR from GitHub
   - Downloads pre-built external libraries
   - Compiles VICAR from source
   
2. **Runtime Stage** (`rockylinux:8`)
   - Minimal runtime dependencies only
   - Copies built VICAR from builder
   - Creates wrapper scripts
   - Sets up environment

This approach keeps the final image size reasonable while ensuring a clean build.

## Differences from Internal Builds

| Feature | Open Source Build | Internal Build (with-rpms) |
|---------|------------------|---------------------------|
| Source | GitHub (public) | JPL Artifactory (internal) |
| VICAR Version | Open source components only | May include mission-specific tools |
| Build Method | Compile from source | Pre-built RPM packages |
| Build Time | 30-60 minutes | 5-10 minutes |
| JPL Certificates | Not required | Required |
| Access | Public | JPL network required |

## Configuration

### Build Arguments

The Dockerfile accepts these build arguments:

- `VICAR_VERSION` (default: `main`) - Git branch or tag to build
- `EXTERNAL_VERSION` (default: `5.0`) - VICAR externals package version
- `EXTERNAL_FILE` (default: `vicar_open_ext_x86-64-linx_5.0.tar.gz`) - Externals tarball name

Example with custom arguments:

```bash
docker build \
  -f docker/Dockerfile \
  -t vicar-native-toolkit:v3.0 \
  --build-arg VICAR_VERSION=v3.0 \
  --build-arg EXTERNAL_VERSION=5.0 \
  .
```

### Environment Variables

The container sets these environment variables:

- `V2TOP=/usr/local/vicar/vos` - VICAR installation directory
- `WORKSPACE=/usr/local/vicar` - Working directory
- `VICSYS=DEVELOPMENT` - VICAR system type
- `LD_LIBRARY_PATH` - Includes all VICAR and external libraries
- `PATH` - Includes VICAR binaries and TAE commands

## Usage Examples

### Interactive Shell

```bash
docker run -it --rm \
  -v $(pwd)/data:/workspace \
  ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource \
  bash
```

Once inside:
```bash
# List available commands
ls /usr/local/bin | head -20

# Run VICAR commands
gen output.vic 512 512
label output.vic
list output.vic
```

### Run Single Command

```bash
# Generate test image
docker run --rm \
  -v $(pwd)/data:/workspace \
  ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource \
  gen /workspace/test.vic 512 512

# Display label
docker run --rm \
  -v $(pwd)/data:/workspace \
  ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource \
  label /workspace/test.vic
```

### With X11 Forwarding (Linux)

For GUI applications:

```bash
# Allow Docker to connect to X server
xhost +local:docker

# Run with X11 socket mounted
docker run -it --rm \
  -v $(pwd)/data:/workspace \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -e DISPLAY=$DISPLAY \
  --network host \
  ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource \
  bash

# Run GUI tools
xvd image.vic
```

### With X11 Forwarding (macOS)

Requires XQuartz:

```bash
# Start XQuartz and allow connections
open -a XQuartz
xhost +localhost

# Run with TCP X11 forwarding
docker run -it --rm \
  -v $(pwd)/data:/workspace \
  -e DISPLAY=host.docker.internal:0 \
  ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource \
  bash
```

## Troubleshooting

### Build Issues

**Problem**: Build fails with "Could not resolve host: github.com"
```bash
# Solution: Check your internet connection and DNS
docker build --network=host ...
```

**Problem**: Build fails downloading externals
```bash
# Solution: Check that the externals version exists
# Visit: https://github.com/NASA-AMMOS/VICAR/releases
# Use the correct version number in build args
```

**Problem**: Out of disk space during build
```bash
# Solution: Clean up Docker and try again
docker system prune -a
docker build ...
```

### Runtime Issues

**Problem**: Command not found
```bash
# Check if wrapper exists
docker run --rm <image> ls /usr/local/bin | grep <command>

# Check VICAR installation
docker run --rm <image> ls -la $V2TOP/p2/lib/x86-64-linx/
```

**Problem**: Library errors (libXXX.so not found)
```bash
# Check LD_LIBRARY_PATH
docker run --rm <image> bash -c 'echo $LD_LIBRARY_PATH'

# List available libraries
docker run --rm <image> ldconfig -p | grep <library>
```

**Problem**: X11 not working
```bash
# Linux: Ensure xhost allows Docker
xhost +local:docker

# macOS: Ensure XQuartz is running and allows connections
xhost +localhost

# Test X11 connection
docker run --rm -e DISPLAY=$DISPLAY <image> xclock
```

## GitHub Actions CI/CD

The repository includes a GitHub Actions workflow that:

1. **Builds** the image on push to main/develop
2. **Tests** basic functionality (smoke tests)
3. **Publishes** to GitHub Container Registry
4. **Tags** appropriately:
   - `opensource` - Latest open-source build
   - `latest` - Latest stable release (main branch)
   - `<branch>` - Branch-specific builds
   - `v*` - Semantic version tags

To trigger a manual build:

1. Go to Actions tab in GitHub
2. Select "Build and Publish VICAR Native Toolkit"
3. Click "Run workflow"
4. Optionally specify VICAR version and externals version

## Image Tags

Available on `ghcr.io/nasa-ammos/tig/vicar-native-toolkit`:

- `:opensource` - Latest open-source build from main branch
- `:latest` - Latest stable release
- `:main` - Latest build from main branch
- `:develop` - Latest build from develop branch
- `:v*` - Specific version tags (e.g., `:v1.0.0`)
- `:<branch>-<sha>` - Specific commit builds

## Contributing

When modifying the open-source build:

1. Test builds locally first
2. Update this README if adding features
3. Ensure the Dockerfile follows best practices:
   - Multi-stage builds for smaller images
   - Minimal runtime dependencies
   - Proper layer caching
   - Security scanning compatibility

## Resources

- **VICAR Source**: https://github.com/NASA-AMMOS/VICAR
- **VICAR Documentation**: https://github.com/NASA-AMMOS/VICAR/wiki
- **VICAR Releases** (for externals): https://github.com/NASA-AMMOS/VICAR/releases
- **Docker Hub**: Not used - we publish to GitHub Container Registry
- **GHCR**: https://github.com/orgs/NASA-AMMOS/packages

## License

This build configuration is part of the TIG project. VICAR itself is licensed under the Apache License 2.0. See the [VICAR repository](https://github.com/NASA-AMMOS/VICAR) for details.

## Support

For issues related to:
- **Build process**: Open an issue in this repository
- **VICAR functionality**: Open an issue in the [VICAR repository](https://github.com/NASA-AMMOS/VICAR/issues)
- **Container runtime**: Check the troubleshooting section above

---

**Note**: This is the open-source build suitable for public distribution and is now the primary/official build method for VICAR Native Toolkit.
