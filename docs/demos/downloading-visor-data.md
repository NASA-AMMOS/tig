# Downloading VISOR Data

VISOR (VIsualization System for Orbital Reconnaissance) calibration and sample data are available from the VICAR GitHub releases but are **not bundled** in the TIG Docker image to reduce image size.

## Quick Download

```bash
# Create directory for VISOR data
mkdir -p visor_data

# Download and extract sample data (~1.3GB)
curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/5.0/visor_sample_data_20230623.tar.gz" | \
  tar -zxf - -C visor_data

# Download and extract Phoenix calibration
curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/5.0/visor_calibration_20230608_phx.tar.gz" | \
  tar -zxf - -C visor_data

# Download and extract MER calibration  
curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/5.0/visor_calibration_20230608_mer.tar.gz" | \
  tar -zxf - -C visor_data
```

**Result:**
```
visor_data/
├── samples/
│   └── sample_data/
│       ├── OrthorectifiedMosaic/    # Pre-computed XYZ point clouds
│       └── StereoCorrelation/       # Stereo image pairs
└── calib/
    ├── phx/                         # Phoenix lander calibration
    └── mer/                         # MER rover calibration
```

## What's Included

### Sample Data (~1.3GB)

Pre-computed stereo data products for testing without running full correlation pipeline:

- **Orthorectified Mosaics**: XYZ point clouds ready for mesh generation
- **Stereo Pairs**: Calibrated stereo images for correlation testing
- **Missions**: Phoenix lander, MER rovers

### Calibration Data (~1.7GB)

Camera models and calibration parameters:

- **Phoenix**: Surface Stereo Imager (SSI) camera models
- **MER**: Navigation Camera (Navcam) and Panoramic Camera (Pancam) models
- **Formats**: CAHVORE camera models, flat field corrections

## Usage with TIG

### With demo-mesh-generation-complete.sh

```bash
# Run demo with VISOR sample data
./demo-mesh-generation-complete.sh --visor-samples visor_data/samples
```

### With Docker directly

```bash
# Mount VISOR data as read-only volumes
docker run -d --name tig-demo \
  -v $(pwd)/workspace:/workspace:Z \
  -v $(pwd)/visor_data/samples:/usr/local/vicar/visor_samples:ro,Z \
  -v $(pwd)/visor_data/calib:/usr/local/vicar/visor_calib:ro,Z \
  ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource
```

### Setting environment variables (optional)

```bash
# Inside container, export paths
export VISOR_SAMPLES=/usr/local/vicar/visor_samples
export VISOR_CALIB=/usr/local/vicar/visor_calib
```

## File Details

### visor_sample_data_20230623.tar.gz

- **Size**: ~1.3GB compressed
- **Extracted**: ~1.35GB
- **Contents**: 
  - NavCam stereo pairs (Phoenix, MER)
  - Pre-computed XYZ point clouds
  - Example disparity maps

**Example files:**
```
samples/sample_data/OrthorectifiedMosaic/
  NLB_712299404XYZ_F0961766NCAM00353M1.IMG  # XYZ point cloud

samples/sample_data/StereoCorrelation/
  NLB_712299404EDR_F0961766NCAM00353M1.IMG  # Left image
  NRB_712299404EDR_F0961766NCAM00353M1.IMG  # Right image
```

### visor_calibration_20230608_phx.tar.gz

- **Size**: ~800MB compressed
- **Mission**: Phoenix Mars Lander
- **Instruments**: Surface Stereo Imager (SSI)

### visor_calibration_20230608_mer.tar.gz

- **Size**: ~900MB compressed  
- **Missions**: Spirit and Opportunity rovers
- **Instruments**: Navcam, Pancam

## Alternative: Download Individual Files

If you only need specific samples, browse releases directly:

https://github.com/NASA-AMMOS/VICAR/releases/tag/5.0

## Disk Space Requirements

| Component | Compressed | Extracted |
|-----------|------------|-----------|
| Sample data | ~1.3GB | ~1.35GB |
| Phoenix calibration | ~800MB | ~850MB |
| MER calibration | ~900MB | ~950MB |
| **Total (all)** | **~3GB** | **~3.15GB** |

## Troubleshooting

### "404 Not Found" errors

Check VICAR releases page for latest version:
```bash
# Replace 5.0 with current version
VICAR_VERSION=5.0
curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/${VICAR_VERSION}/visor_sample_data_20230623.tar.gz"
```

### Extraction fails

Ensure `tar` supports gzip:
```bash
# Extract in two steps
curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/5.0/visor_sample_data_20230623.tar.gz" -o visor_samples.tar.gz
tar -zxf visor_samples.tar.gz -C visor_data
```

### Slow download

Use `wget` with resume capability:
```bash
wget -c "https://github.com/NASA-AMMOS/VICAR/releases/download/5.0/visor_sample_data_20230623.tar.gz"
```

## Related Documentation

- [VICAR Releases](https://github.com/NASA-AMMOS/VICAR/releases)
- [Mesh Generation Demo](demos/mesh-generation.md)
- [Getting Started](getting-started.md)
