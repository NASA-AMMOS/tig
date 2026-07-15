# TIG Architecture

Overview of the Terrain Intelligence Generator system components.

## System Components

```
┌─────────────────────────────────────────────────────────┐
│                    TIG Container                         │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   VICAR     │  │  MARS Tools  │  │   Vicario    │  │
│  │  Programs   │  │              │  │  (Java JAR)  │  │
│  │  (~540)     │  │  marscorr    │  │              │  │
│  │             │  │  marscor3    │  │  Image       │  │
│  │  gen        │  │  marsxyz     │  │  Converter   │  │
│  │  label      │  │  marsmesh    │  │              │  │
│  │  list       │  │  marsmap     │  │  VICAR→PNG   │  │
│  └─────────────┘  └──────────────┘  └──────────────┘  │
│                                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │           M2020 Calibration Data                │  │
│  │  - Camera models (NavCam, Mastcam-Z)           │  │
│  │  - Flat field corrections                       │  │
│  │  - Geometric distortion models                  │  │
│  └─────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
    Input Images         Processing            Output Meshes
    (VICAR .VIC)       (Workspace)          (OBJ, PNG, XYZ)
```

## Processing Pipeline

### Full Correlation Pipeline

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

## Core Tools

### VICAR Programs
- **Base**: Full VICAR image processing suite (~540 CLI wrappers on `PATH`)
- **Location**: `/usr/local/bin/` (wrappers) → `/usr/local/vicar/dev/`
- **Runtime**: TAE (Terminal Application Executive)

### MARS Tools
Specialized Mars terrain processing:

| Tool | Function | Input | Output |
|------|----------|-------|--------|
| marscorr | Initial correlation | 2 images | Disparity map |
| marscor3 | Multi-pass refinement | Disparity + images | Refined disparity |
| marsxyz | 3D triangulation | Disparity + images | XYZ point cloud |
| marsmesh | Surface meshing | XYZ + texture | OBJ mesh |
| marsmap | Orthoprojection | XYZ | Map projection |

### Vicario (Java)
- **Purpose**: VICAR format conversion
- **Technology**: Java 11 + Java Advanced Imaging
- **Features**: 
  - Dynamic range rescaling (16-bit → 8-bit)
  - Format support: PNG, JPEG, TIFF
  - Proper VICAR label parsing

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

### M2020 Calibration Structure

```
mars_calibration_m20/
├── camera_models/
│   ├── M20_SN_0103.cahvore  # NavCam Left
│   ├── M20_SN_0102.cahvore  # NavCam Right
│   ├── ZL*.cahvore          # Mastcam-Z Left
│   └── ZR*.cahvore          # Mastcam-Z Right
├── flat_fields/
│   └── *.parms              # Flat field corrections
└── param_files/
    ├── M20_camera_mapping.xml
    └── MSL_camera_mapping.xml
```

### Camera Models
- **CAHVORE**: Camera model format (Center, Axis, Horizontal, Vertical, Optical, Radial, Entrance)
- **Purpose**: Geometric projection, distortion correction
- **Usage**: Automatic lookup by MARS tools based on image labels

## Docker Architecture

### Image Layers

```
Base Layer: Oracle Linux 8
    ↓
Builder Stage: downloads pre-built VICAR + external library releases
    ↓
Runtime Layer: VICAR binaries + MARS tools + Java + vicario.jar + calibration
    ↓
Command Wrappers: ~540 CLI wrappers generated under /usr/local/bin
    ↓
Entry Point: Shell with VICAR environment
```

### Volume Mounts

- `/workspace` - Input/output files
- `/usr/local/vicar/mars_calib` - M2020 calibration (read-only)
- `/usr/local/vicar/visor_data` - Sample data (optional)

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

- Container runs as root (VICAR requirement)
- Volume mounts use `:Z` flag for SELinux compatibility
- Calibration mounted read-only (`:ro`)
- No network access required
