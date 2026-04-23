# Quick Reference: VICAR Native Toolkit (Open Source)

## Pull & Run

```bash
# Pull latest open-source build
docker pull ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource

# Run with workspace
docker run -it --rm -v $(pwd)/data:/workspace ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource bash
```

## Common Commands

```bash
# Generate test image
gen output.vic 512 512

# Display label information
label image.vic

# List image contents
list image.vic

# Convert VICAR to PNG (if vic2pic available)
vic2pic image.vic image.png

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

## Troubleshooting

```bash
# Check if image exists locally
docker images | grep vicar-native-toolkit

# Remove old image
docker rmi ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource

# Pull latest
docker pull ghcr.io/nasa-ammos/tig/vicar-native-toolkit:opensource

# Check container logs (if running detached)
docker logs <container-id>

# Enter running container
docker exec -it <container-id> bash
```

## Links

- **Documentation**: [OPENSOURCE-BUILD.md](OPENSOURCE-BUILD.md)
- **VICAR Source**: https://github.com/NASA-AMMOS/VICAR
- **TIG Repository**: https://github.com/NASA-AMMOS/tig
- **Container Registry**: https://github.com/orgs/NASA-AMMOS/packages
