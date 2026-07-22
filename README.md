# Terrain Intelligence Generator (TIG)

Open source VICAR image processing environment for planetary science and stereo terrain reconstruction.

## Overview

TIG provides a containerized VICAR execution environment with ~550 image processing commands spanning enhancement, filtering, geometric transformation, format conversion, and multi-mission calibration. Built on VICAR (Video Image Communication and Retrieval), NASA JPL's general-purpose image processing system used across planetary missions since the 1960s. While TIG's flagship capability is stereo terrain reconstruction, it provides comprehensive image processing tools for planetary science workflows. The vicar-native-toolkit provides native-like CLI access to all VICAR commands.

## Features

### Terrain Reconstruction (Flagship Capability)
- **Stereo Correlation**: Generate disparity maps from stereo image pairs (marscorr, marscor3)
- **3D Point Clouds**: Convert disparity to XYZ coordinates (marsxyz)
- **Mesh Generation**: Create textured 3D surface meshes in OBJ / OpenInventor formats (marsmesh)
- **Terrain Analysis**: Orthoprojection, mosaicking, localization (marsmap, marsmos, marsautoloco)

### Image Processing (~550 Commands)
- **Enhancement**: Contrast stretching, filtering, dynamic range adjustment (stretch, filter)
- **Geometric Operations**: Transformations, rotation, resizing, registration (geom, rotate, size)
- **Format Conversion**: VICAR to/from PNG, JPEG, TIFF (vicario)
- **Analysis**: Histograms, statistics, pixel inspection (hist, list, label)
- **Mathematical Operations**: Image arithmetic, band math (f2)

### Multi-Mission Support
- **VISOR Integration**: 1,461 calibration files for M20, MSL, MER, Phoenix missions
- **Camera Models**: CAHVORE format support with automatic calibration lookup
- **Sample Data**: 249 sample files including stereo pairs and pre-computed XYZ

### Development Tools
- **Native Toolkit**: ~550 command wrappers for native-like CLI usage
- **Fast Execution**: Long-running container with minimal latency (~50-100ms)
- **Cross-Platform**: Linux, macOS (including Apple Silicon via emulation)

## Quick Start

### Option 1: Automated Native Toolkit (Recommended)

Get native-like VICAR commands in one step:

```bash
cd vicar-native-toolkit
make bootstrap
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

### VICAR Native Toolkit

A wrapper system that provides native-like CLI usage for all ~550 VICAR commands inside the TIG Docker execution environment. Features:
- ✨ **One-command setup** via `make bootstrap`
- 🚀 **Fast activation** (~1 second, symlink-based wrappers)
- 🔧 **Auto-discovers** all ~550 VICAR commands
- 🐳 **Custom image support** via `IMAGE=` variable
- 📊 **VISOR calibration mounting** for terrain processing
- 🌐 **Full VICAR access** - not just terrain tools, but all image processing commands

📁 `vicar-native-toolkit/`  
📖 [Toolkit README](vicar-native-toolkit/README.md) | [Quick Reference](vicar-native-toolkit/docs/QUICKREF.md)

### Terrain Intelligence Generator
A containerized VICAR execution environment, packaged as a Docker image with the complete VICAR toolset (~550 commands), VISOR calibration integration, and optimized runtime for both interactive and batch processing workflows.
- 📁 `terrain-intelligence-generator/docker/`
- 📖 [Getting Started](docs/getting-started.md)

**Image Variants:**
- **`tig:opensource`** (~2GB) - Complete VICAR system with 976 commands
- **`tig:geocal`** (~3-4GB) - VICAR + GeoCal geometric calibration & bundle adjustment
- 📖 [GeoCal Integration Guide](docs/geocal-integration.md)

### VISOR (VICAR Institutional Stereo Observation Repository)
Open source repository containing camera calibration files for multiple missions including M20 (Mars 2020), MER, MSL, and others. TIG integrates with VISOR for accurate stereo processing.

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

### Terrain Reconstruction Pipeline
| Tool | Purpose | Input | Output |
|------|---------|-------|--------|
| `marscorr` | Initial stereo correlation | Stereo pair | Disparity map |
| `marscor3` | Disparity refinement | Disparity + images | Refined disparity |
| `marsxyz` | 3D point generation | Disparity + images | XYZ point cloud |
| `marsmesh` | Surface triangulation | XYZ + texture | 3D mesh (OBJ) |
| `marsmap` | Orthoprojection | Images + geometry | Map-projected images |

### Image Processing Commands (~550 Available)
| Tool | Purpose | Category |
|------|---------|----------|
| `vicario` | VICAR ↔ PNG/JPEG/TIFF | Format conversion |
| `gen` | Generate test images | Development |
| `stretch` | Contrast adjustment | Enhancement |
| `filter` | Spatial filtering | Enhancement |
| `geom` | Geometric transformation | Geometric |
| `hist` | Histogram analysis | Analysis |
| `label` | VICAR metadata viewer | Metadata |
| `list` | Pixel value display | Analysis |
| `f2` | Image arithmetic | Mathematical |

*TIG provides ~550 total VICAR commands. Above shows representative examples.*

## Requirements

- Docker or Podman
- 8GB RAM minimum (16GB recommended for high-res meshes)
- Linux, macOS, or Windows with WSL2

## Project Structure

```
tig/
├── demo-mesh-generation-with-xyz.sh    # Main demo script (stereo or pre-computed XYZ)
├── demo-mesh-native-toolkit.sh         # Demo using the native toolkit wrappers
├── find-calibration.sh                 # Calibration helper
├── docs/                               # Documentation
│   ├── demos/                          # Demo guides
│   ├── architecture/                   # System design
│   └── reference/                      # Tool references
├── vicar-native-toolkit/               # VICAR wrapper scripts
└── terrain-intelligence-generator/     # TIG Docker execution environment
    └── docker/
        ├── Dockerfile
        └── vicario.jar                 # Image converter
```

## Contributing

Contributions welcome! This project uses:
- **VICAR**: JPL's MIPL general-purpose image processing system (~550 commands)
- **Docker**: Containerized VICAR execution environment
- **VISOR**: Open source calibration repository for multiple missions
- **Open Source**: Community-driven planetary image processing and terrain reconstruction tools

## License

Apache License 2.0 (see LICENSE file)

## About VICAR

VICAR (Video Image Communication and Retrieval) is a general-purpose image processing system developed by NASA JPL's Multimission Image Processing Laboratory (MIPL). Used for processing images from Mars rovers, lunar missions, and deep space probes since the 1960s. VICAR provides comprehensive image processing capabilities including enhancement, filtering, geometric transformation, radiometric calibration, stereo reconstruction, and format conversion. TIG makes this powerful system accessible through modern containerization.

## Acknowledgments

- NASA JPL Multimission Image Processing Laboratory (MIPL)
- VICAR development team
- Open source planetary science community
