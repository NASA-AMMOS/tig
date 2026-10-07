# TIG Documentation

Documentation for the **Terrain Intelligence Generator (TIG)** — a containerized VICAR image processing environment with 546 commands for planetary image analysis, enhancement, transformation, and stereo terrain reconstruction.

New here? Start with **[Getting Started](getting-started.md)**.

## Contents

### Getting Started
- **[Getting Started](getting-started.md)** — Prerequisites, installation, and your first demo.
- **[Installing on macOS](install-macos.md)** — Step-by-step Podman and XQuartz setup, including Apple Silicon emulation.

### Demos
- **[Mesh Generation](demos/mesh-generation.md)** — Mars 2020 NavCam stereo terrain reconstruction walkthrough (flagship capability).
- **[Panorama Mosaic](demos/panorama-mosaic.md)** — 360-degree in-situ NavCam panorama in a cylindrical, polar or vertical projection.
- **[Surface Characteristics](demos/surface-characteristics.md)** — Slope, roughness, surface normals and placement goodness from an XYZ cloud.
- **[Co-registration](demos/co-registration.md)** — Tiepoints, pointing correction, and the two-epoch change product composed from them (`demo-change-monitoring.sh`).
- **[Building From Source](demos/building-from-source.md)** — Patch a VICAR program locally, build it with `tig --build`, and run it in the container.
- **[Demo Commands](demos/commands.md)** — Complete VICAR pipeline, command by command.
- **[Downloading VISOR Data](demos/downloading-visor-data.md)** — Obtaining calibration and sample data from VICAR releases.

### Architecture
- **[Components](architecture/components.md)** — Overview of the TIG system components and VICAR capabilities.

### Reference
- **[Vicario](reference/vicario.md)** — Java VicarIO library for VICAR image-format conversion.
- **[Calibration Data](reference/calibration-data.md)** — Mounting MARS/VISOR calibration files.
- **[Project Requirements Gate](reference/project-requirements-gate.md)** — The PR check for documentation parity, broad deployability and test coverage.

### Examples
- **[MMGIS Integration](../examples/mmgis-integration/README.md)** — Turning a TIG mosaic and terrain mesh into rendered layers in NASA-AMMOS MMGIS.

## Related

- **[Project README](../README.md)** — Top-level project overview.
- **[tig-cli](../tig-cli/README.md)** — The command-line client that runs all 546 VICAR tools.
- **[TIG VICAR image](../terrain-intelligence-generator/README.md)** — Building and testing the container image, including the release visual regression suite.
