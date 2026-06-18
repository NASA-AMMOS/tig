# Terrain Intelligence Generator (TIG)

Mars 2020 stereo terrain reconstruction pipeline using NASA's VICAR image processing system.

## Overview

TIG provides Docker-based tools for generating 3D terrain meshes from Mars rover stereo camera images. Built on VICAR (Video Image Communication and Retrieval), NASA JPL's image processing system used across planetary missions.

## Features

- **Stereo Correlation**: Generate disparity maps from stereo image pairs (marscorr, marscor3)
- **3D Point Clouds**: Convert disparity to XYZ coordinates (marsxyz)
- **Mesh Generation**: Create textured 3D surface meshes (marsmesh)
- **Format Conversion**: Export to OBJ, OpenInventor, GLB formats
- **M2020 Support**: Includes Mars 2020 NavCam and Mastcam-Z calibration

## Quick Start

### Option 1: Automated Native Toolkit (Recommended)

Get native-like VICAR commands in one step:

```bash
cd vicar-native-toolkit
./bootstrap.sh
# ✓ Pulls Docker image
# ✓ Starts container  
# ✓ Creates ~550 command wrappers
# ✓ Ready in <30 seconds

# Now use VICAR commands directly
gen out=test.img nl=10 ns=10
toolkit-status
```

See [vicar-native-toolkit/README.md](vicar-native-toolkit/README.md) for details.

### Option 2: Run Mesh Generation Demo

```bash
# Pull the Docker image
docker pull ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource

# Run NavCam mesh generation demo
./demo-mesh-generation-with-xyz.sh \
  --stereo-left /path/to/left.VIC \
  --stereo-right /path/to/right.VIC
```

**Output**: Textured 3D mesh in Wavefront OBJ format (~10 minutes)

### View Results

```bash
# Generated files in workspace/
ls workspace/
# terrain.obj       - 3D mesh
# terrain.mtl       - Material file
# texture.png       - Texture image
# pointcloud.xyz    - XYZ point cloud

# View in MeshLab, Blender, or CloudCompare
meshlab workspace/terrain.obj
```

## Components

## Components

### VICAR Native Toolkit

Docker environment with VICAR tools wrapped for native-like CLI usage. Features:
- ✨ **One-command setup** via `bootstrap.sh`
- 🚀 **Fast activation** (~1 second, symlink-based wrappers)
- 🔧 **Auto-discovers** ~550 VICAR commands
- 🐳 **Custom image support** via `--image` flag
- 📊 **MARS calibration mounting** for terrain processing

📁 `vicar-native-toolkit/`  
📖 [Toolkit README](vicar-native-toolkit/README.md) | [Quick Reference](vicar-native-toolkit/QUICKREF.md)

### Terrain Intelligence Generator
Pre-built demos and M2020 calibration for mesh generation.
- 📁 `terrain-intelligence-generator/docker/`
- 📖 [Getting Started](docs/getting-started.md)

### Demos
Example workflows for stereo mesh generation.
- 📁 Demo scripts: `demo-mesh-generation*.sh`
- 📖 [Mesh Generation Guide](docs/demos/mesh-generation.md)
- 📖 [Command Reference](docs/demos/commands.md)

## Documentation

- **[Getting Started](docs/getting-started.md)** - Installation and setup
- **[Mesh Generation Demo](docs/demos/mesh-generation.md)** - Step-by-step mesh creation
- **[Command Reference](docs/demos/commands.md)** - Available VICAR commands
- **[Vicario Reference](docs/reference/vicario.md)** - Image format conversion

## Key Tools

| Tool | Purpose | Input | Output |
|------|---------|-------|--------|
| `marscorr` | Initial stereo correlation | Stereo pair | Disparity map |
| `marscor3` | Disparity refinement | Disparity + images | Refined disparity |
| `marsxyz` | 3D point generation | Disparity + images | XYZ point cloud |
| `marsmesh` | Surface triangulation | XYZ + texture | 3D mesh (OBJ) |
| `vicario` | Format conversion | VICAR image | PNG/JPEG/TIFF |

## Requirements

- Docker or Podman
- 8GB RAM minimum (16GB recommended for high-res meshes)
- Linux, macOS, or Windows with WSL2

## Project Structure

```
tig/
├── demo-mesh-generation-with-xyz.sh    # Main demo script
├── demo-mesh-generation.sh             # Full correlation pipeline
├── find-calibration.sh                 # Calibration helper
├── docs/                               # Documentation
│   ├── demos/                          # Demo guides
│   ├── architecture/                   # System design
│   └── reference/                      # Tool references
├── vicar-native-toolkit/               # VICAR wrapper environment
└── terrain-intelligence-generator/     # TIG Docker image
    └── docker/
        ├── Dockerfile
        ├── vicario.jar                 # Image converter
        └── mars_calibration_m20/       # M2020 calibration
```

## Contributing

Contributions welcome! This project uses:
- **VICAR**: JPL's MIPL image processing system
- **Docker**: Containerized VICAR environment
- **Mars 2020**: Perseverance rover calibration data

## License

Apache License 2.0 (see LICENSE file)

## About VICAR

VICAR (Video Image Communication and Retrieval) is a general-purpose image processing system developed by NASA JPL's Multimission Image Processing Laboratory (MIPL). Used for processing images from Mars rovers, lunar missions, and deep space probes since the 1960s.

## Acknowledgments

- NASA JPL Multimission Image Processing Laboratory (MIPL)
- Mars 2020 Perseverance Rover Team
- VICAR development team
