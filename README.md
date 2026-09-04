# Terrain Intelligence Generator (TIG)

Open source planetary image processing and terrain reconstruction environment,
built on NASA JPL's VICAR.

## Overview

TIG works with the instrument-specific formats planetary missions produce,
converting between them and into interchange formats while retaining the
acquisition metadata that travels in the image label. It processes raw
instrument image products into the visual and geometric products that surface
mission operations run on: disparity maps, XYZ point clouds, textured terrain
meshes, slope, roughness and reachability rasters, and map-projected mosaics
that can cover a full 360 degrees in azimuth. Camera-model and coordinate-frame
tools bring products from different instruments into a common frame, so views
from several cameras can be combined; radiometric calibration and image
co-registration are available where the mission's calibration data and tiepoint
workflows are supplied. Every tool is an ordinary command, so terrain
generation can be automated as ordinary scripts or workflow tasks.

It packages VICAR — NASA JPL's general-purpose image processing system, used on
planetary missions since the 1960s — as a container image with 546 commands
(74 of them the mission-specific `mars*` terrain programs), plus
[`tig`](tig-cli/README.md), a CLI that runs any of them from your own shell as
if they were installed locally. Products come out in interchange formats
(Wavefront OBJ, glTF/GLB, PNG/JPEG/TIFF, map-projected VICAR) that downstream
AMMOS visualization tools such as MMGIS, ASTTRO and Astria consume; TIG itself
does not talk to those services and ships no adapter for them.

Scope note: processing starts at instrument image products (EDR/FDR-level VICAR
images). There is no telemetry ingest or depacketization in this repository —
"raw" here means uncalibrated image products, not raw downlink.

## Key Capabilities

### Surface Reconstruction

Terrain meshes, point clouds and slope/roughness maps from in-situ imagery:

| Stage | Tools |
| --- | --- |
| Stereo correlation | `marscorr`, `marscor3`, `marsecorr`, `marsjplstereo` |
| Point clouds | `marsxyz`, `marsxyzmerge`, `marsxyzsurf`, `marsrfilt` |
| Meshes | `marsmesh`, `marsrefmesh` (Wavefront OBJ + OpenInventor), `obj2gltf` (glTF/GLB) |
| Surface characteristics | `marsslope`, `marsrough`, `marsirough`, `marsuvw` (surface normals), `marsgreach` (goodness/reachability) |
| Range and depth | `marsrange`, `marsdepth`, `marsinvrange` |

The [mesh generation demo](docs/demos/mesh-generation.md) runs the stereo →
disparity → XYZ → mesh path end to end on Mars 2020 NavCam pairs, and the
[Airflow example](examples/airflow-k8s-pipeline/README.md) runs the same path as
scheduled tasks. The [surface characteristics demo](docs/demos/surface-characteristics.md)
takes that XYZ and derives slope, roughness, surface normals and the placement
goodness raster that `marsigood` builds from tilt and roughness (step 7 of that
demo). The separate reachability goodness raster comes from `marsgreach`, which
is in the image but only runs when the demo is given `--reach` with a 6-band arm
reachability product; that product is produced by a mission program that is not
in the image, so `marsgreach` stays an available program rather than a
demonstrated workflow.

### Orbital Mapping and Monitoring

Map-projected, large-area products are built by mosaicking overlapping frames.
`marsmap` assembles a mosaic in a cylindrical, polar, vertical or (experimental)
sinusoidal projection and handles azimuth wrap-around, which is how a panorama
covering up to 360 degrees is produced; `marsmos` assembles frames under a
synthetic wide-field camera model; `marsortho` produces orthographic mosaics and
DEMs from XYZ data; `marsremos` and `marsunmosaic` rebuild and invert mosaics.
`map3`, `maptran` and `mapcoord` from the general VICAR toolset perform
cartographic map projection and reprojection.

Co-registration is a tiepoint-and-pointing workflow rather than a single
command: `marsautotie` / `marsautotie2` / `marstie` generate tiepoints,
`marsnav`, `marsnav2` (bundle adjustment) and `marsautoloco` solve for corrected
pointing, and `marsfidfinder` locates fiducials. Once images are registered,
change comparison over time is composed from the general image-processing tools
— there is no change-detection program in the image.

Both workflows are demonstrated: see the [panorama mosaic](docs/demos/panorama-mosaic.md)
and [co-registration](docs/demos/co-registration.md) demos. Note also
that the `mars*` mosaicking programs are built around in-situ camera geometry
(spherical coordinates about a landing site); orbital imagery is handled by the
general cartographic programs above.

### Integrated Data Products

Camera models in CAHV/CAHVOR/CAHVORE (`marscahv`, `marsmake_cm`, `marsget_cm`,
`marscheckcm`) and frame transforms (`marscoordtrans`, `marsproj`,
`marsrelabel`) bring products from different instruments and coordinate frames
into a common frame, which is what allows high-resolution surface views and
broader context imagery to be combined into one product. Radiometric
calibration (`marsrad`) plus brightness matching and colour handling
(`marsbrt`, `marsrcorr`, `marsbias`, `marscolor`, `marsdebayer`) normalize
inputs beforehand; `marsrad` reads flat fields from `MARS_CONFIG_PATH`, so it
needs mission calibration data that the base image does not bundle — see
[Calibration Data](docs/reference/calibration-data.md) for mounting VISOR data
or using the `:visor-<mission>` image variants. `marsrad` is exercised as the
`rad_left` / `rad_right` tasks of the [Airflow
example](examples/airflow-k8s-pipeline/README.md).

## Supporting Capabilities

### Format conversion with metadata retention

VICAR's label system carries acquisition metadata through processing, so
intermediate and final products keep their provenance (`label`, `clabel` and
`marsrelabel` inspect and update it). `vicario` converts VICAR images to
PNG/JPEG/TIFF (see the [reference](docs/reference/vicario.md)); `vtiff` handles
TIFF, `visis2` / `visisx` / `isislab` handle ISIS, and `obj2gltf` / `obj2plane`
/ `marstile` convert mesh and tiled products. There is no PDS4 reader or writer
in the image; metadata retention here means VICAR-label retention.

### General image processing

546 commands for enhancement (`stretch`, `filter`), geometry (`size`, `lgeom`,
`mgeom`, `polygeom`, `rotate2`), analysis (`hist`, `list`, `label`) and
arithmetic (`f2`).

### Automation

Every tool is an ordinary command, so pipelines are ordinary scripts — the
[demo script](demo-mesh-generation-with-xyz.sh) is one, and the
[Airflow + Kubernetes example](examples/airflow-k8s-pipeline/README.md) runs
radiometric correction, correlation, XYZ and meshing as event-driven DAG tasks.
`tig` keeps a container warm between invocations, so per-command overhead is
tens of milliseconds rather than a container start.

### Not currently provided

So the scope is unambiguous:

- No telemetry ingest or depacketization; inputs are instrument image products.
- No ASTTRO or Astria adapter, exporter or tiling recipe. TIG writes interchange
  formats those tools can consume; connecting them is up to you. MMGIS is the
  exception: [`examples/mmgis-integration/`](examples/mmgis-integration/README.md)
  is a worked export and tiling recipe that was run end to end.
- No PDS4 reader or writer.
- No change-detection program; change monitoring is a composed workflow.
- No calibration data in the base image (the `:visor-<mission>` variants bundle
  it per mission).
- No worked example for `marsgreach` reachability, whose input-producing program
  is not in the image — the program is present, the demo is not. The image
  smoke test (`terrain-intelligence-generator/test-docker-image.sh`) covers the
  CLI, container layout, format conversion and the presence of a handful of
  command names; it runs no MARS terrain program. The end-to-end product paths
  that are demonstrated are the mesh, panorama mosaic, surface characteristics,
  co-registration and change-monitoring demos, and the Airflow example.

## Quick Start

```bash
pip install tig-cli

# Any VICAR tool, running in the container against your local files
tig gen test.vic 512 512
tig vicario test.vic test.png
```

Prefer the tools unqualified? Generate a shim directory once:

```bash
tig --shim
export PATH="$HOME/.local/share/tig/shims:$PATH"
marsmesh inp=pointcloud.xyz out=terrain.obj in_skin=texture.img -adaptive
```

Generate a mesh from a Mars 2020 NavCam stereo pair:

```bash
export MARS_CONFIG_PATH=/path/to/mars_calibration_m20
./demo-mesh-generation-with-xyz.sh \
  --stereo-left /path/to/NLM_*_FDR_*.VIC \
  --stereo-right /path/to/NRM_*_FDR_*.VIC

ls workspace/          # terrain.obj, terrain.mtl, texture.png, pointcloud.xyz
meshlab workspace/terrain.obj
```

See [QUICKSTART.md](QUICKSTART.md) for the fuller tour.

## Components

### tig-cli

The command-line client. Runs any VICAR tool in the container, translating host
paths, reusing one warm container, mounting calibration data, and forwarding X11
so GUI tools such as `xvd` display on your desktop.

📁 `tig-cli/` · 📦 [`pip install tig-cli`](https://pypi.org/project/tig-cli/) · 📖 [README](tig-cli/README.md)

### TIG VICAR image

The container image: VICAR built from the
[NASA-AMMOS/VICAR](https://github.com/NASA-AMMOS/VICAR) open-source releases,
plus the Java `vicario` converter. Published as
`ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource`. Release
sign-off runs `terrain-intelligence-generator/test-release-regression.sh`, which
replays the demos on real VISOR frames and reports every product with an image.

📁 `terrain-intelligence-generator/` · 📖 [README](terrain-intelligence-generator/README.md)

### VISOR

VICAR Institutional Stereo Observation Repository — camera calibration files for
M20, MSL, MER and other missions. Not bundled in the base image; mount it at
runtime, or use a `:visor-<mission>` or `:fullfeatured` image variant that
bundles it.

`./fetch-calibration.sh --list` shows what the VICAR release publishes and
`./fetch-calibration.sh m20` downloads, verifies and installs it; the demos offer
this themselves when they find no calibration.

📖 [Downloading VISOR Data](docs/demos/downloading-visor-data.md) · [Calibration Data](docs/reference/calibration-data.md)

### Fullfeatured image variant

The base image plus M20 VISOR calibration, so MARS calibration-dependent
programs run with nothing downloaded and nothing mounted. Opt-in via
`CONTAINER_IMAGE`; the tig default image is unchanged.

📁 `terrain-intelligence-generator/fullfeatured/` · 📖 [README](terrain-intelligence-generator/README.md#fullfeatured-variant)

### Demos

📁 `demo-mesh-generation-with-xyz.sh` · 📖 [Mesh Generation](docs/demos/mesh-generation.md) · [Command Reference](docs/demos/commands.md)

📁 `demo-surface-characteristics.sh` · 📖 [Surface Characteristics](docs/demos/surface-characteristics.md)

📁 `demo-panorama-mosaic.sh` · 📖 [Panorama Mosaic](docs/demos/panorama-mosaic.md)

📁 `demo-co-registration.sh` · 📖 [Co-registration](docs/demos/co-registration.md)

📁 `demo-change-monitoring.sh` · 📖 [Change Monitoring](docs/demos/co-registration.md#change-monitoring) (documented with co-registration, whose pointing solution it consumes)

## Documentation

- **[Getting Started](docs/getting-started.md)** - Installation and setup
- **[Quick Start](QUICKSTART.md)** - Common workflows end to end
- **[Mesh Generation Demo](docs/demos/mesh-generation.md)** - Step-by-step mesh creation
- **[Panorama Mosaic Demo](docs/demos/panorama-mosaic.md)** - 360-degree in-situ NavCam panorama
- **[Surface Characteristics Demo](docs/demos/surface-characteristics.md)** - Slope, roughness, normals and goodness from an XYZ cloud
- **[Co-registration Demo](docs/demos/co-registration.md)** - Tiepoints, pointing correction, and the two-epoch change product composed from them
- **[Command Reference](docs/demos/commands.md)** - Tour of the VICAR toolset
- **[Vicario Reference](docs/reference/vicario.md)** - Image format conversion
- **[Calibration Data](docs/reference/calibration-data.md)** - Mounting MARS/VISOR files
- **[Architecture](docs/architecture/components.md)** - How the pieces fit together
- **[Airflow + Kubernetes Pipeline](examples/airflow-k8s-pipeline/README.md)** - Event-driven terrain mesh generation example
- **[MMGIS Integration](examples/mmgis-integration/README.md)** - Getting a TIG mosaic and mesh onto a map in NASA-AMMOS MMGIS
- **[Agent Skills](.agents/skills/)** - `tig-setup` plus one `tig-generate-*` skill per demo product, `tig-export-to-mmgis`, and `tig-demo-testing` for verifying the demos

## Key Tools

### Terrain reconstruction pipeline

| Tool | Purpose | Input | Output |
|------|---------|-------|--------|
| `marscorr` | Initial stereo correlation | Stereo pair | Disparity map |
| `marscor3` | Disparity refinement | Disparity + images | Refined disparity |
| `marsxyz` | 3D point generation | Disparity + images | XYZ point cloud |
| `marsrfilt` | Rover hardware filtering | XYZ | Filtered XYZ |
| `marsmesh` | Surface triangulation | XYZ + texture | 3D mesh (OBJ) |
| `marsslope`, `marsrough` | Surface characteristics | XYZ | Slope / roughness maps |
| `marsmap` | Projected mosaicking (cylindrical / polar / vertical) | Images + geometry | Map-projected mosaic |
| `marsmos` | Camera-model mosaicking | Images + geometry | Wide-field mosaic |
| `marsortho` | Orthographic mosaic / DEM | XYZ + skin | Ortho image, DEM |

### General image processing

| Tool | Purpose | Category |
|------|---------|----------|
| `vicario` | VICAR ↔ PNG/JPEG/TIFF | Format conversion |
| `gen` | Generate test images | Development |
| `stretch` | Contrast adjustment | Enhancement |
| `filter` | Spatial filtering | Enhancement |
| `size` | Resample / zoom | Geometric |
| `rotate2` + `lgeom` | Rotation: `rotate2` writes the transform, `lgeom` applies it | Geometric |
| `hist` | Histogram analysis | Analysis |
| `label -list inp=<file>` | VICAR metadata viewer (TAE proc: the subcommand is a flag) | Metadata |
| `f2` | Image arithmetic | Mathematical |

*Representative examples out of 546 commands; `tig bash -c 'ls /usr/local/bin'`
lists them all.*

### Exit Codes

VICAR programs return 1 on a successful run, and 1 again when TAE rejects the
invocation, so the raw code cannot tell the two apart. TIG's command wrappers
translate them, which means `set -e` and `&&` chains work as written:

| Code | Meaning |
|------|---------|
| 0 | The program ran |
| 1 | TAE rejected the invocation (missing parameter, unknown keyword) |
| 255 | The program called `abend()` — e.g. a missing or unreadable input |
| >128 | Killed by a signal |

The translation happens in the wrappers under `/usr/local/bin`, so it applies
to commands run through `tig-cli` or a runtime's `exec`. Calling a program by its
full path (`$V2TOP/p2/lib/x86-64-linx/gen`) bypasses it and returns VICAR's
raw code.

## Requirements

- A container runtime: Docker, Podman, nerdctl or Finch (whichever is on
  `PATH`; set `TIG_CONTAINER_RUNTIME` or the `runtime` config key to choose)
- Python 3.9+
- 8GB RAM minimum (16GB recommended for high-res meshes)
- Linux, macOS (including Apple Silicon, via emulation), or Windows with WSL2

On macOS, see [Installing on macOS](docs/install-macos.md) for the Podman and
XQuartz setup the GUI tools need.

## Project Structure

```
tig/
├── demo-mesh-generation-with-xyz.sh    # Mesh demo (stereo pair or pre-computed XYZ)
├── demo-surface-characteristics.sh     # Slope, roughness, normals and goodness from XYZ
├── demo-panorama-mosaic.sh             # 360-degree in-situ NavCam panorama mosaic
├── demo-co-registration.sh             # Tiepoints and pointing correction
├── demo-change-monitoring.sh           # Two-epoch change product from registered frames
├── find-calibration.sh                 # Calibration helper
├── fetch-calibration.sh                # Download open-source VISOR calibration
├── tig-cli/                            # The tig command-line client (PyPI: tig-cli)
├── terrain-intelligence-generator/     # Container image: Dockerfile, vicario, build/test
├── QUICKSTART.md                       # Common workflows end to end
├── examples/
│   ├── airflow-k8s-pipeline/           # Airflow + Kubernetes terrain pipeline example
│   └── mmgis-integration/              # TIG products as MMGIS layers
└── docs/
    ├── demos/                          # Demo guides
    ├── architecture/                   # System design
    └── reference/                      # Tool references
```

## Contributing

Contributions welcome! This project builds on:
- **VICAR**: JPL MIPL's general-purpose image processing system
- **OCI containers**: Portable VICAR execution environment
- **VISOR**: Open source calibration repository for multiple missions

## License

Apache License 2.0 (see LICENSE file)

## About VICAR

VICAR (Video Image Communication and Retrieval) is a general-purpose image
processing system developed by NASA JPL's Multimission Image Processing
Laboratory (MIPL). Used for processing images from Mars rovers, lunar missions,
and deep space probes since the 1960s, it covers enhancement, filtering,
geometric transformation, radiometric calibration, stereo reconstruction, and
format conversion. TIG makes it accessible through modern containerization.

## Acknowledgments

- NASA JPL Multimission Image Processing Laboratory (MIPL)
- VICAR development team
- Open source planetary science community
