---
name: tig-generate-terrain-mesh
description: Generate a textured 3D terrain mesh (terrain.obj + terrain.mtl + texture.png) from a NavCam stereo pair or a pre-computed XYZ point cloud with demo-mesh-generation-with-xyz.sh. Use when asked for a mesh, OBJ, point cloud, disparity map or XYZ product from rover stereo imagery, or as the first step towards surface characteristics or an MMGIS model layer.
---

# Generate a terrain mesh

Script: `demo-mesh-generation-with-xyz.sh` (run from the repo root, writes to
`workspace/`). Reference: `docs/demos/mesh-generation.md`. Complete the
`tig-setup` skill first (tig CLI, calibration for the input mission).

## Choose a mode

| Mode | Inputs | Time | When |
| --- | --- | --- | --- |
| Full stereo | `--stereo-left L --stereo-right R` | ~5-10 min (1280x960 M20 or 1024x1024 MSL) | You have a left/right pair; also produces the XYZ cloud used by `tig-generate-surface-characteristics` |
| Quick | `--xyz cloud.IMG --texture image.IMG` | ~90 s | You already have an XYZ product **whose label carries the stereo baseline** (M2020 VISOR XYZ do; MSL sample XYZ do not) |

Inputs must be from the same mission as `MARS_CONFIG_PATH`, and left/right
must be the same acquisition (same sclk and sequence in the filename, e.g.
`NLF_0650_0724654097_444EDR_...` / `NRF_0650_0724654097_444EDR_...`).

## Run

```bash
# full stereo pipeline (M20 pair, m20 calibration)
export MARS_CONFIG_PATH=~/.mars_calib/m20
./demo-mesh-generation-with-xyz.sh \
  --stereo-left  NLF_0650_0724654097_444EDR_N0320000NCAM08111_01_295J01.IMG \
  --stereo-right NRF_0650_0724654097_444EDR_N0320000NCAM08111_01_295J01.IMG

# quick mode on an existing cloud
./demo-mesh-generation-with-xyz.sh --xyz pointcloud.IMG --texture image.IMG
```

Without `--texture`, stereo mode textures with the **right** image; quick mode
requires `--texture` (the script rejects `--stereo-left` without
`--stereo-right`, so it is not a texture-only alternative).
Non-interactive shells that have no calibration must set
`TIG_FETCH_CALIBRATION=1` (or fetch it beforehand).

**`marscorr` needs a seed inside its search reach.** `marscorr` uses no camera
models; it grows the disparity map from a seed tiepoint (`seed=(l,s,l',s')`,
default `(124,127,126,108)`, searched over `amax(2)`=81 px). Close-range pairs
such as the MSL sample `StereoCorrelation/NLB_712299404EDR_F0961766NCAM00353M1`
/ `NRB_...` (~180 px disparity mid-frame) exit the script at stage 1 with
`Correlation failure for seed #0 patch / No valid seed points found!`. The
script has no seed option, so run the stages by hand from `workspace/` with a
measured seed (pick a textured rock and find the matching pixel in the right
eye; the region grows from there, so one good seed is enough):

```bash
export MARS_CONFIG_PATH=~/.mars_calib/msl
cd workspace
cp ~/visor_data/sample_data/StereoCorrelation/NLB_712299404EDR_F0961766NCAM00353M1.IMG left.vic
cp ~/visor_data/sample_data/StereoCorrelation/NRB_712299404EDR_F0961766NCAM00353M1.IMG right.vic
cp right.vic texture.img
tig marscorr \( left.vic right.vic \) disparity_init.img template=15 search=51 quality=0.2 \
  seed=\(300,512,302,328\)                       # ~4 min, ~876k tiepoints
# then the marscor3 ... vicario lines below unchanged -> 324k-triangle terrain.obj
```

What the script runs, for tuning or re-running a single stage from inside
`workspace/`:

```bash
tig marscorr \( left.vic right.vic \) disparity_init.img template=15 search=51 quality=0.2
tig marscor3 \( left.vic right.vic \) disparity.img in_disp=disparity_init.img \
  template=11 search=31 quality=0.4 -omp_on
tig marsxyz  \( left.vic right.vic \) pointcloud.xyz disp=disparity.img \
  error=10.0 abserr=0.15 lined=100 avgline=50 zlimit=\(-300,300\) spike_range=0.04 outlier=0.5
tig marsrfilt inp=pointcloud.xyz out=pointcloud_filtered.xyz
tig marsmesh inp=pointcloud_filtered.xyz out=terrain.obj in_skin=texture.img \
  x_subsample=1 y_subsample=1 range_min=0.2 range_mid=100 range_max=100 \
  lod_levels=10 max_angle=87.5 res_min=3000 res_max=500000 density=1 -adaptive maxgap=5
tig vicario texture.img texture.png
```

`marscorr`/`marscor3` are the slow stages; `-omp_on` uses all cores.

## Outputs (`workspace/`)

| File | What | Sanity check |
| --- | --- | --- |
| `terrain.obj` | Mesh with UVs; 40-300 MB, 0.2-1.2 M vertices depending on scene range | `grep -c '^v ' terrain.obj` > 100000; `grep -c '^f '` > 0 |
| `terrain.mtl` | Material referencing `texture.png` | `grep map_Kd terrain.mtl` |
| `texture.png` | Texture (input image size) | `file texture.png` shows PNG with the frame's dimensions |
| `pointcloud.xyz`, `pointcloud_filtered.xyz` | 3-band REAL XYZ (stereo mode); filtered = rover hardware removed | `tig label -list pointcloud_filtered.xyz` shows `NB=3`, `FORMAT='REAL'` |
| `pointcloud_input.xyz` | The supplied cloud (quick mode) | |
| `disparity_init.img`, `disparity.img` | Coarse and refined disparity (stereo mode) | mostly non-zero over the scene |
| `terrain.lbl`, `terrain.iv` | marsmesh siblings; not needed downstream | |

Downstream:
- `tig-generate-surface-characteristics` takes `workspace/pointcloud_filtered.xyz`
  and `workspace/texture.img`.
- `tig-export-to-mmgis` takes `workspace/terrain.obj` (with `texture.png` beside it).

## Troubleshooting

- `Stereo baseline not found in label, must be provided in parameter` from
  `marsmesh`: the `--xyz` cloud lacks the baseline (typical of MSL sample XYZ).
  Use the stereo pipeline instead, or use the cloud only for surface
  characteristics.
- `ERROR: marscorr failed to generate disparity_init.img` right after
  `Running initial correlation`: `No valid seed points found!` - the default
  seed is out of reach for this pair; run `marscorr` by hand with `seed=` as
  shown above (or `seedfile=` from `marstie`), then finish the chain manually.
- `marscorr`/`marsxyz` fail with a camera-model error: calibration is for the
  wrong mission or `MARS_CONFIG_PATH` is a wrapper directory (needs
  `camera_models/` directly inside).
- Mesh is tiny or `res_min` warnings: the disparity is mostly invalid. Check
  `disparity.img` is not blank, and that left/right are a true stereo pair.
- `texture.png` missing but `texture.img` present: `vicario` failed; the script
  warns and continues. Convert by hand with
  `tig stretch inp=texture.img out=t8.img -astretch percent=2 dnmin=0 dnmax=255` then
  `tig vicario t8.img texture.png`.
- The script clears `terrain.*`, `texture.*`, `disparity*.img` and
  `pointcloud*.xyz` from `workspace/` before starting; copy earlier products
  you want to keep.
