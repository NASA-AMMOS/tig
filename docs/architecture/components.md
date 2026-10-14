# TIG Architecture

Overview of the Terrain Intelligence Generator system components and VICAR image processing environment.

## System Components

```
┌─────────────────────────────────────────────────────────┐
│                    TIG Container                         │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   VICAR     │  │  MARS Tools  │  │   Vicario    │  │
│  │  Commands   │  │    (74)      │  │  (Java JAR)  │  │
│  │   (546)     │  │              │  │              │  │
│  │             │  │  marscorr    │  │  Image       │  │
│  │  gen        │  │  marscor3    │  │  Converter   │  │
│  │  label      │  │  marsxyz     │  │              │  │
│  │  stretch    │  │  marsmesh    │  │  VICAR→PNG   │  │
│  │  filter     │  │  marsmap     │  │  PNG→VICAR   │  │
│  │  lgeom      │  │  marsmos     │  │              │  │
│  │  hist       │  │  + 68 more   │  │              │  │
│  │  + 540 more │  │              │  │              │  │
│  └─────────────┘  └──────────────┘  └──────────────┘  │
│                                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │   Calibration mount (VISOR, supplied by you)    │  │
│  │   /usr/local/vicar/mars_calib  (read-only)      │  │
│  │  - M20, MSL, MER, Phoenix camera models         │  │
│  │  - Flat field corrections                       │  │
│  │  - Geometric distortion models                  │  │
│  └─────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
    Input Images         Processing            Output Files
    (VICAR .VIC)       (Workspace)       (OBJ, PNG, VICAR, etc.)
```
```

## Processing Pipeline

### Full Stereo Terrain Reconstruction Pipeline (Flagship Capability)

```
Stereo Pair (L/R .VIC)
    │
    ├─► marscorr ────► disparity_init.img
    │   (template=15, search=51)
    │
    ├─► marscor3 ────► disparity.img
    │   (refine, quality=0.4)
    │
    ├─► marsxyz ─────► pointcloud.xyz
    │   (triangulation)
    │
    ├─► marsmesh ────► terrain.obj + terrain.mtl
    │   (surface mesh)
    │
    └─► vicario ─────► texture.png
        (format convert)
```

### Quick Pipeline (Pre-computed XYZ)

```
XYZ Point Cloud (.IMG)
    │
    ├─► marsmesh ────► terrain.obj + terrain.mtl
    │   (surface mesh)
    │
    └─► vicario ─────► texture.png
        (texture convert)
```

## Execution Model

[`tig`](../../tig-cli/README.md) keeps one container warm and runs each tool in
it via the container runtime's `exec` (Docker, Podman, nerdctl or Finch), as your
host user, with host paths translated so files resolve the same inside and out.
`tig --shim` additionally writes one command per VICAR tool onto your `PATH`.

## Core Tools

### VICAR Commands (546 Available)
- **Base**: Full VICAR image processing suite for planetary science
- **Categories**:
  - **Image Generation**: gen, copy
  - **Enhancement**: stretch, filter, histogram equalization
  - **Geometric**: size, lgeom, mgeom, polygeom, rotate2 (transform for lgeom), registration
  - **Analysis**: hist, list, label, statistics
  - **Mathematical**: f2 (image arithmetic), band operations
  - **Multispectral**: band manipulation, transformations
- **Location**: `/usr/local/bin/` (wrappers) → `/usr/local/vicar/dev/`
- **Runtime**: TAE (Terminal Application Executive)

### MARS Terrain Tools (74 Commands)
Specialized Mars terrain processing suite:

| Tool | Function | Input | Output |
|------|----------|-------|--------|
| marscorr | Initial correlation | 2 images | Disparity map |
| marscor3 | Multi-pass refinement | Disparity + images | Refined disparity |
| marsxyz | 3D triangulation | Disparity + images | XYZ point cloud |
| marsmesh | Surface meshing | XYZ + texture | OBJ mesh |
| marsmap | Cylindrical/polar/vertical mosaicking | Multiple images (+ nav table) | Projected mosaic |
| marsmos | Mosaicking under a synthetic wide-field camera model | Multiple images (+ nav table) | Mosaic |
| marsortho | Orthographic mosaicking and DEM generation | XYZ (+ skin images) | Ortho mosaic, DEM |
| marsautotie | Tie point detection | Image pair | Tie points |
| marsrfilt | Rover filtering | XYZ | Filtered XYZ |

### Vicario (Java)
- **Purpose**: VICAR format conversion (VICAR ↔ standard formats)
- **Technology**: Java 17 + Java Advanced Imaging; [NASA-AMMOS/vicario](https://github.com/NASA-AMMOS/vicario) from Maven Central
- **Features**: 
  - Dynamic range rescaling (16-bit → 8-bit)
  - Format support: PNG, JPEG, TIFF (read and write)
  - Proper VICAR label parsing
  - Bidirectional conversion

## Data Flow

### Input Requirements

**NavCam Stereo Pair**:
- Left: `NL[M|B]_<SCLK>_*FDR_*.VIC`
- Right: `NR[M|B]_<SCLK>_*FDR_*.VIC`
- Format: VICAR, 16-bit grayscale
- Typical size: 1280x960 or 5120x3840

**Mastcam-Z Stereo Pair**:
- Left: `ZL[F|R]_<SCLK>_*[FDR|RAS]_*.VIC`
- Right: `ZR[F|R]_<SCLK>_*[FDR|RAS]_*.VIC`
- Format: VICAR, 16-bit RGB or grayscale
- Typical size: 1648x1200

### Output Formats

**Mesh Files**:
- `.obj` - Wavefront OBJ (vertices + faces)
- `.mtl` - Material file (texture reference)
- `.iv` - OpenInventor format
- `.lbl` - PDS label metadata

**Texture Files**:
- `.png` - Portable Network Graphics
- `.jpg` - JPEG (optional)
- Grayscale or RGB depending on input

**Point Cloud**:
- `.xyz` - VICAR XYZ format (3-band REAL)
- Coordinate frame: SITE_FRAME or ROVER_NAV_FRAME

## Calibration Data

### Multi-Mission Calibration Structure (VISOR Integration)

```
mars_calibration_m20/
├── camera_models/
│   ├── M20_SN_0103.cahvore  # NavCam Left
│   ├── M20_SN_0102.cahvore  # NavCam Right
│   ├── ZL*.cahvore          # Mastcam-Z Left
│   └── ZR*.cahvore          # Mastcam-Z Right

mars_calibration_msl/
mars_calibration_mer/
mars_calibration_phoenix/
├── camera_models/
├── flat_fields/
│   └── *.parms              # Flat field corrections
└── param_files/
    ├── M20_camera_mapping.xml
    ├── MSL_camera_mapping.xml
    └── MER_camera_mapping.xml

```

Calibration is not part of the image; tig mounts a host directory of it
read-only. See [Calibration Data](../reference/calibration-data.md).

### Camera Models
- **CAHVORE**: Camera model format (Center, Axis, Horizontal, Vertical, Optical, Radial, Entrance)
- **Purpose**: Geometric projection, distortion correction
- **Usage**: Automatic lookup by MARS tools based on image labels

## Container Architecture

### Image Layers

```
Base Layer: Oracle Linux 8
    ↓
Builder Stage: downloads pre-built VICAR + external library releases
    ↓
Runtime Layer: VICAR binaries (546 commands) + MARS tools (74) + Java + vicario (Maven Central)
    ↓
Command Wrappers: 546 CLI wrappers generated under /usr/local/bin
    ↓
Entry Point: Shell with VICAR environment
```

### Volume Mounts

tig mounts these; see the [tig-cli README](../../tig-cli/README.md).

- `$HOME` and the current directory - read-write, at their host paths
- `/host` - the rest of the host filesystem, read-only
- `/usr/local/vicar/mars_calib` - calibration data, read-only
- extra read-write paths via `--writable-path`

### Environment Variables

- `V2TOP` - VICAR installation root
- `MARS_CONFIG_PATH` - Calibration path for MARS tools
- `TAE` - TAE configuration directory

## Performance Characteristics

### Processing Time (1280x960 images)

| Stage | Tool | Time | Parallelizable |
|-------|------|------|----------------|
| Initial correlation | marscorr | ~6 min | CPU cores |
| Refinement | marscor3 | ~2 min | Yes (-omp_on) |
| XYZ generation | marsxyz | ~1 min | No |
| Mesh creation | marsmesh | ~30 sec | No |
| Texture convert | vicario | <1 sec | No |
| **Total** | | **~10 min** | |

### Memory Requirements

- **Minimum**: 8GB RAM
- **Recommended**: 16GB RAM
- **High-res meshes**: 32GB RAM (5120x3840 inputs)

### Disk Usage

- **Container**: ~3.1GB
- **Per mesh output**: ~300MB (1280x960 input)
- **Temporary files**: ~30MB (disparity maps)

## Security Considerations

- Commands run as your host user, so outputs are owned by you
- On SELinux Enforcing hosts tig passes `--security-opt label=disable`
- Host filesystem outside `$HOME` and the working directory is read-only
- Calibration mounted read-only
- No network access required, apart from pulling the image
