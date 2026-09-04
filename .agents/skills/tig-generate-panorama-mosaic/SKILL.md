---
name: tig-generate-panorama-mosaic
description: Generate an in-situ panorama mosaic (cylindrical, polar or vertical) from rover NavCam or Mastcam-Z frames with demo-panorama-mosaic.sh - radiometric correction, seam brightness matching, marsmap projection and PNG. Use when asked for a panorama, mosaic, 360 view, overhead/vertical view, or the mosaic input for an MMGIS tile layer.
---

# Generate a panorama mosaic

Script: `demo-panorama-mosaic.sh` (run from the repo root, writes to
`workspace/`). Reference: `docs/demos/panorama-mosaic.md`. Complete `tig-setup`
first (tig CLI, calibration for the frames' mission).

## Choose frames

- All frames from **one rover position**: same site/drive counter and,
  normally, same sequence in the product name
  (`NLF_0300_..._N0090000NCAM00501_...` -> site/drive `N0090000`, sequence
  `NCAM00501`). A frame taken after a drive lands in the wrong place.
- Use one camera eye (all `NL*` or all `NR*`) and one product size - PDS
  directories also hold thumbnails of the same acquisition (e.g. Mastcam-Z
  `..._1100LUJ02.IMG` next to `..._110085J01.IMG`); a careless glob mixes them.
- For a closed 360 ring the azimuths must overlap around the circle (M20 NavCam
  is ~96 deg wide, so 4 frames ~90 deg apart close it). Gaps simply stay black.
- Radiometrically correctable products: EDR/FDR/RAD `.IMG` or `.VIC` with an
  intact VICAR/ODL label. Calibration must cover the instrument or `marsrad`
  produces nothing (the script stops at that frame).
- MSL sample data: `~/visor_data/sample_data/CylindricalMosaic/NLB_*NCAM00293*.IMG`
  (5 frames, ~110 deg of azimuth) with `MARS_CONFIG_PATH=~/.mars_calib/msl`.
  Mars 2020: the sol-300 `NCAM00501` left FDR frames from
  `https://planetarydata.jpl.nasa.gov/img/data/mars2020/mars2020_navcam_ops_calibrated/data/sol/00300/ids/fdr/ncam/`
  with `m20` calibration.

## Run

```bash
export MARS_CONFIG_PATH=~/.mars_calib/m20

# cylindrical 0-360 (default)
./demo-panorama-mosaic.sh /path/to/sol300/NLF_0300_*NCAM00501*.IMG

# cylindrical, fitted to the frames (no black canvas around a partial ring)
./demo-panorama-mosaic.sh --auto-extent --bbox /path/to/frames/*.IMG

# polar (nadir in the middle); --up-az puts that azimuth at the top
./demo-panorama-mosaic.sh --projection polar --top-el 30 frames/*.IMG

# vertical / overhead, metres in the SITE frame, north up - required for MMGIS tiles
./demo-panorama-mosaic.sh --projection vertical \
  --min-x -15 --max-x 15 --min-y -15 --max-y 15 --vert-scale 0.03 frames/*.IMG
```

**Vertical extents are SITE-frame metres, not metres from the rover.** Read the
rover's SITE position from a frame label (`ORIGIN_OFFSET_VECTOR` of the
`ROVER_NAV_FRAME` entry, or the `Projection origin = (x, y, z)` line a
cylindrical run prints) and centre `--min/max-x/y` on its x, y. The MSL sample
NCAM00293 frames sit at (-99, 61, -18): `--min-x -129 --max-x -69 --min-y 31
--max-y 91 --vert-scale 0.05` gives a 1200x1200 60 m plan view; the README's
`-30..30` window is empty for them. The script also leaves the projection
plane at SITE z = 0, so when the rover's z is not ~0 (18 m above it here)
everything is smeared outward by `z / tan(elevation)`. Re-run the final stage
by hand with the plane through the rover instead (same frames and gains):

```bash
cd workspace
tig marsmap inp=panorama_frames.txt out=panorama.img -norad -nogrid projection=vertical \
  minx=-129 maxx=-69 miny=31 maxy=91 vert_scale=0.05 surf_coord=ROVER brtcorr=panorama_brtcorr.xml
tig stretch inp=panorama.img out=panorama_stretched.img -astretch percent=2 dnmin=0 dnmax=255
tig vicario panorama_stretched.img panorama.png
```

Options that matter most: `--left-az/--right-az/--top-el/--bottom-el` (extent
in degrees), `--wrap-az DEG` (where a 360 ring is cut), `--zoom F` (scale
relative to the camera's natural scale; `--zoom 0.5` halves the output - use for
narrow-FOV Mastcam-Z), `--grid` (draw the az/el graticule; off by default so
the pixels stay clean), `--bbox` (write per-frame footprints to
`panorama_bbox.csv`), `--no-brightness-match`, `--no-stretch`.

Stages the script runs (from `workspace/`), for re-running one by hand:

```bash
tig marsrad inp=FRAME.IMG out=panorama_rad/000_FRAME.rad.img          # once per frame
tig marsmap inp=panorama_frames.txt out=panorama_overlap_mosaic.img \
  ovr_out=panorama_overlaps.xml -norad -nogrid zoom=0.25 projection=cylindrical leftaz=0 rightaz=360
tig marsbrt inp=panorama_frames.txt in_ovr=panorama_overlaps.xml out=panorama_brtcorr.xml \
  out_solution_id=TIGDEMO do_what=DO_MULT
tig marsmap inp=panorama_frames.txt out=panorama.img -norad -nogrid \
  projection=cylindrical leftaz=0 rightaz=360 brtcorr=panorama_brtcorr.xml
tig stretch inp=panorama.img out=panorama_stretched.img -astretch percent=2 dnmin=0 dnmax=255
tig vicario panorama_stretched.img panorama.png
```

`panorama_frames.txt` lists the `marsrad` outputs in stacking order; it must
contain container-visible paths (see `tig-setup`). The overlap pass and the
final pass must use identical projection arguments or the gains apply to the
wrong pixels.

## Outputs (`workspace/`)

| File | What | Sanity check |
| --- | --- | --- |
| `panorama.img` | The mosaic; 3-band for M20 NavCam/Mastcam-Z RGB FDRs, 1-band for MSL | `tig label -list panorama.img`: expected size, e.g. 4646x1182x3 for 360 deg at 12.9 px/deg; label carries the projection, `START_AZIMUTH`/`STOP_AZIMUTH` and scale |
| `panorama.png` | 8-bit display version, 2% stretch | open it; a 360 ring from one tier has a dark band on top - judge the imagery, not the canvas |
| `panorama_rad/*.rad.img` | Radiometrically corrected frames | one per input frame |
| `panorama_overlaps.xml` | Overlap statistics between frames | `grep -c '<overlap ' panorama_overlaps.xml` > 0 when frames overlap |
| `panorama_brtcorr.xml` | Per-frame gains from `marsbrt` | gains in ~0.7-1.3 for a sane sequence |
| `panorama_bbox.csv` | Frame footprints as CSV/WKT (`--bbox`) | |

Downstream: `tig-export-to-mmgis` needs a **vertical**-projection
`panorama.img`; cylindrical/polar mosaics cannot be georeferenced by it.

## Troubleshooting

- Frames stacked in the wrong place / duplicated ground: frames from different
  site/drives. Filter by the `N0xxxxxx` field in the filename.
- Exit 136 from `marsmap`: MPI/hwloc crash on older images; prefix with
  `tig env HWLOC_COMPONENTS=-x86 marsmap ...` or update the image.
- `marsrad produced nothing`: calibration is for a different mission or
  instrument; run the printed `tig marsrad inp=... out=/tmp/x.img` to see why.
- Visible seams: brightness matching was skipped (`--no-brightness-match`) or
  `panorama_overlaps.xml` is empty because frames do not overlap in the chosen
  extent.
- Mostly black PNG at the right size: the frames cover a small part of the
  0-360 x el canvas. Use `--auto-extent` or explicit `--left-az/--right-az`.
- Vertical mosaic all zero (`tig maxmin inp=panorama.img` max 0) or the rover
  sits at an edge: extents not centred on the rover's SITE x, y and/or
  projection plane at the wrong height - see the vertical note above.
- Polar mosaic has a hole in the centre: frames do not look at the nadir; that
  is correct behaviour.
- Mastcam-Z: run with `--auto-extent --zoom 0.5`. Label `INSTRUMENT_AZIMUTH`
  is not the footprint azimuth for this narrow-FOV camera, so do not derive
  `--left-az/--right-az` from labels; read the fitted range back from the
  output label. Only `ZCAM_L0_RGB` 3-band frames have been exercised; do not
  mix narrowband single-band filters into the same mosaic.
