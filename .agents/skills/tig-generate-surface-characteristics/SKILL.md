---
name: tig-generate-surface-characteristics
description: Generate terrain-analysis rasters from an XYZ point cloud with demo-surface-characteristics.sh - surface normals, slope, slope heading, northerly tilt, solar energy, roughness, and instrument-placement tilt/goodness maps, each as VICAR .img plus a fixed-range PNG. Use when asked for slope, roughness, normals, traversability, or instrument/arm placement products from rover stereo data.
---

# Generate surface characteristics

Script: `demo-surface-characteristics.sh` (run from the repo root, writes to
`workspace/`). Reference: `docs/demos/surface-characteristics.md`. Complete
`tig-setup` first.

## Input

One 3-band REAL XYZ point cloud with an intact VICAR label (camera model,
coordinate frame and site are read from it), from the same mission as
`MARS_CONFIG_PATH`:

- `workspace/pointcloud_filtered.xyz` from `tig-generate-terrain-mesh` (stereo
  mode) - the usual path; also pass `--texture workspace/texture.img`.
- An existing XYZ product, e.g. MSL sample
  `~/visor_data/sample_data/OrthorectifiedMosaic/NLB_712299404XYZ_F0961766NCAM00353M1.IMG`
  with `msl` calibration. Unlike `marsmesh`, these programs do **not** need the
  stereo baseline in the label, so MSL sample clouds work here.

## Run

```bash
export MARS_CONFIG_PATH=~/.mars_calib/m20
./demo-surface-characteristics.sh \
  --xyz workspace/pointcloud_filtered.xyz \
  --texture workspace/texture.img \
  --solar-angle 60
```

Options: `--instrument heli|seis|hp3|wts` (placement products; default
`heli`), `--coord site|local_level|fixed|rover|instrument` (frame for the slope
products; default `site`), `--solar-angle DEG` (sun elevation at local noon;
enables `solar.img`), `--reach FILE` (6-band arm reachability product; enables
`marsgreach` -> `reach_goodness.img`).

Stages the script runs (about 1-3 minutes), for tuning by hand from
`workspace/`:

```bash
tig marsuvw inp=cloud.xyz out=normals_slope.uvw -slope radius=10 separation=0.5 error=0.02 box_radius=1000 coord=site
tig marsslope inp=cloud.xyz uvw=normals_slope.uvw out=slope.img   type=slope   coord=site   # also heading, ntilt
tig marsslope inp=cloud.xyz uvw=normals_slope.uvw out=solar.img   type=solar   coord=site sa=60
tig marsuvw inp=cloud.xyz out=normals_arm.uvw x_center=2 box_radius=5
tig marsrough inp=cloud.xyz uvw=normals_arm.uvw out=roughness.img x_center=2 y_center=0 box_radius=5 max_rough=0.05 bad_rough=0.1
tig marsitilt inp=cloud.xyz out=tilt_heli.img uix_out=uix_heli.img zix_out=zix_heli.img -heli
tig marsirough inp=cloud.xyz out=iroughness_heli.img uix=uix_heli.img zix=zix_heli.img -heli   # abends, optional
tig marsigood inp=tilt_heli.img out=goodness_heli.img band=1 thresh=5
tig cform slope.img s8.img oform=byte irange=\(0,30\) orange=\(0,255\) && tig vicario s8.img slope.png
```

The `marsuvw -slope` parameters are what make the product usable: with the
default `error=0.0005` only ~4% of pixels get a normal; `error=0.02
separation=0.5 box_radius=1000` gives ~75%.

## Outputs (`workspace/`)

All rasters are 1-band REAL at the XYZ image size with 0 as the missing value,
unless noted. PNGs use fixed physical ranges (via `cform`) so grey levels are
comparable between runs.

| File | Meaning | PNG range | Sanity check |
| --- | --- | --- | --- |
| `slope.img/.png` | Slope, degrees (0 = level) | 0-30 | `tig hist slope.img -nohist`: non-zero MAX. DN and a mean of roughly 5-25 deg (zeros included); the MSL sample outcrop cloud from `tig-generate-terrain-mesh` gives mean 13.6, stddev 17 |
| `heading.img/.png` | Azimuth the slope faces, degrees | -180..180 | |
| `ntilt.img/.png` | North-facing tilt component, degrees | -30..30 | |
| `solar.img/.png` | Relative solar energy from tilt (`--solar-angle`) | 0-1 | |
| `roughness.img/.png` | Peak-to-peak deviation from the local plane, metres | 0-0.05 | not almost all invalid |
| `normals_slope.uvw`, `normals.png` | Rover-scale unit normals, 3-band REAL (U,V,W) | -1..1 as RGB | `w` ~ -1 on level ground (Z is down in site/local_level) |
| `normals_arm.uvw` | Instrument-scale normals | | |
| `tilt_<inst>.img/.png` | Placement tilt: 3 bands (status, min, max) | 0-5 | |
| `uix_<inst>.img` (3-band), `zix_<inst>.img` (1-band) | Instrument index images from `marsitilt` | | |
| `goodness_<inst>.img/.png` | Combined placement goodness 0-5 | 0-5 | |
| `iroughness_<inst>.img` | Instrument roughness - **not produced**: `marsirough` abends on every input (upstream VICAR bug); script reports and continues | | |
| `reach_goodness.img/.png` | `marsgreach` output (`--reach`) | 0-5 | only meaningful for a real 6-band reachability product |
| `scene.png` | `--texture` converted for context | | |

Check dimensions and format with `tig label -list slope.img` (`NB=1`,
`FORMAT='REAL'`, `NL`/`NS` equal to the cloud's).

## Troubleshooting

- Slope map nearly empty (few % of pixels): `marsuvw -slope` ran with the
  default `error`; use the script's `error=0.02 separation=0.5 box_radius=1000`.
- Roughness nearly all invalid: `x_center`/`box_radius` still describe the MER
  IDD workspace (1.2 m around x=1) or `max_rough` is at its 0.015 default.
- Every PNG black except a fringe: converted with `vicario` alone; go through
  `cform` with a physical `irange` first, as above.
- `marsirough` `Exception in XVREAD ... zix_*.img` / `ABEND`: expected, see
  `terrain-intelligence-generator/test-marsirough-abend.sh`; `goodness_*` is
  still computed from the tilt status band.
- Calibration errors even though no image is read: the camera model comes from
  the XYZ label; `MARS_CONFIG_PATH` must hold that mission's `camera_models/`.
- Wrong frame: `--coord site` is the verified default; other frames run but
  were not validated.
