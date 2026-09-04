---
name: tig-generate-change-monitoring
description: Generate a two-epoch change product with demo-change-monitoring.sh - joint pointing solve across epochs, identical marsmap renders, radiometrically normalised difference rasters (raw, gain, linear, BRTCORR), and the registration-floor controls needed to interpret them. Use when asked to compare repeat coverage of the same scene, detect change between sols, or difference two rover images.
---

# Generate a two-epoch change product

Script: `demo-change-monitoring.sh` (run from the repo root, writes to
`workspace-change/` or `--workspace DIR`). Reference:
`docs/demos/co-registration.md`, "Change monitoring" and "Two-epoch change
product" sections. Complete `tig-setup` first.

There is no change-detection program in the image. This workflow composes one:
`marschkovl` -> `marsautotie` -> `marsnav` (one joint solution over both
epochs) -> `marsmap` per epoch with the **same** nav table and **identical**
projection -> `f2` differences -> controls. The product is a difference raster
with a measured registration floor, not a change map.

## Choose inputs

- Two epochs of the **same scene from the same rover position** (same
  site/drive; the rover did not move). Pointing correction is angular - frames
  from different positions will not register (that needs XYZ + `marsortho`).
- Same instrument, same product family (e.g. both `NLF_*RAD*` left NavCam),
  same band count.
- Ideally matched local solar time. Illumination differences dominate the raw
  difference otherwise (the verified M20 sol 649/650 pair, 3.5 h apart in LTST,
  differs by ~3x in mean DN).
- Optional `--tie-extra` frames from either epoch strengthen the joint solve
  but are not rendered or differenced.
- Verified data: M20 `NLF_0649_0724552533_722RAD_N0320000NCAM08111_0A0095J01.IMG`
  and `NLF_0650_0724654126_005RAD_N0320000NCAM08111_0A0095J01.IMG` from
  `mars2020_navcam_ops_calibrated` (PDS), `m20` calibration.
  Smoke test without M20 data: two MSL
  `~/visor_data/sample_data/CylindricalMosaic/NLB_*NCAM00293*.IMG` frames as the
  two "epochs" with `msl` calibration (exercises the pipeline; not a real
  change product).

## Run

```bash
./demo-change-monitoring.sh \
  --epoch1 NLF_0649_0724552533_722RAD_N0320000NCAM08111_0A0095J01.IMG \
  --epoch2 NLF_0650_0724654126_005RAD_N0320000NCAM08111_0A0095J01.IMG \
  --tie-extra sol649_extra.lis --tie-extra sol650_extra.lis \
  --calibration ~/.mars_calib/m20 \
  --scale 40 --bounds "0 93 0 -70" --box "100 300 2200 3100"
```

`--epoch1/--epoch2/--tie-extra` take a frame or a `.lis` file (host paths, one
per line) and are repeatable. Other options: `--calibration DIR` (else
`MARS_CONFIG_PATH` / `find-calibration.sh`), `--workspace DIR`, `--overlap PCT`
(40), `--density N` (50), `--grid-spacing N` (40), `--max-residual PX` (5),
`--solution-id ID` (`CHANGE`), `--scale PX_PER_DEG` and `--bounds "L R T B"`
(azimuth left/right, elevation top/bottom; default from the geometry probe),
`--band N` (1), `--box "SL SS NL NS"` (statistics rectangle; default the
centred 40% region - must contain no 0-DN margin or `maxmin` refuses it),
`--no-brtcorr`.

Run once with defaults first: the script prints the probe's natural scale and
az/el bounds, and the statistics box it chose; then pin `--scale`, `--bounds`
and `--box` so later runs are pixel-comparable. Expect ~5-10 minutes for two
full M20 NavCam frames plus four tie frames.

Stages: label/solar-geometry report -> `marschkovl` -> `marsautotie` ->
`marsnav -remove` -> `marsmap` probe -> `marsmap` overlap-statistics pass ->
`marsbrt do_what=DO_MULT` -> `marsmap` per epoch (same `navtable=`, same
projection args, `grid=NOGRID`) -> `hist`/`maxmin` box statistics -> `f2`
differences -> controls (`marsmap` re-render + `difpic`, `copy` shifts of
1/2/3 px, render without nav table) -> `f2`/`vicario` display products. Every
program's output is logged to `<stage>.log` in the workspace.

## Outputs (`workspace-change/`)

| File | What |
| --- | --- |
| `pointing.nav`, `tiepoints.tpt`, `kept.tpt` | Joint navigation solution over all frames (`joint.lis`) |
| `epoch1_raw.img`, `epoch2_raw.img` | Cylindrical renders, identical geometry (HALF) |
| `epoch1_brt.img`, `epoch2_brt.img` | Same, with `marsbrt` BRTCORR applied |
| `diff_raw.img` | `in1-in2` (REAL) |
| `diff_gain.img` | `in1-G*in2`, G = mean1/mean2 |
| `diff_lin.img` | `in1-G2*in2-O2`, G2 = std1/std2, O2 matches means - **the usable normalisation** |
| `diff_brt.img` | difference of the BRTCORR renders |
| `diffview.img/.png` | `diff_lin` scaled so 0 -> 128 and +/-3 sigma -> 0/255 |
| `epoch1_display.png`, `epoch2_display.png` | Stretched epoch renders |
| `epoch1_repeat_raw.img`, `diff_shift{1,2,3}.img`, `epoch1_nonav.img`, `diff_nav.img` | Controls |
| `stats_*.txt`, `maxmin_*.txt` | Box statistics per product |
| `joint.ovr`, `joint.brt`, `probe.img`, `joint_overlap.img` | Overlap pass and radiometric solve |

The script ends with a `=== Numbers Summary ===`. Read it like this:

- `Residual before/after`: after must be ~1-2 px, with most tiepoints kept.
- `Determinism: 0 differences`: renders are bit-exact, so nothing in the
  difference is pipeline noise. Non-zero means something is wrong.
- `Shift-control stdevs (1/2/3 px)`: the registration floor. A change signal
  whose sigma is at or below the 1-px control (sigma ~134 DN on the M20 pair)
  is indistinguishable from sub-pixel mis-registration.
- `Nav-effect stdev` should be below the 1-px control while `Nav-effect
  difpic` changes millions of pixels: the correction is real and sub-pixel.
- Linear difference sigma should be **lower** than raw; gain-only is often
  worse (contrast, not just level, differs). A `BRTCORR ... ill-conditioned`
  warning means `diff_brt` is not a normalised change - use `diff_lin`.
- `Linear difference sigma is zero`: the epochs are identical in the box (e.g.
  the same frame passed twice), not a detected change.

## Troubleshooting

- `marschkovl` accepts no cross-epoch pair: the epochs do not see the same
  ground or pointing differs by more than the matcher's search; check the
  printed overlap %.
- `statistics box ... does not fit` / `maxmin` refuses the box: pass `--box`
  inside the imagery, ending before line `NL-1` and sample `NS-4` of the
  render.
- `no measurements for frame keys: N` warning: a `--tie-extra` frame lies
  outside `--bounds`, so `marsbrt` gives it an unconstrained multiplier; widen
  `--bounds` or drop the frame from the BRTCORR path (`--no-brtcorr`).
- Graticule residue in the difference: a `marsmap` call ran without
  `grid=NOGRID`; the script's shared parameter array prevents this - do not
  edit one render without the other.
- Exit 136 from `marsmap`: MPI/hwloc; prefix `tig env HWLOC_COMPONENTS=-x86`
  or update the image.
- The script aborts with no message: a validation helper's error went to a
  captured stdout; re-run the stage shown last in the workspace `.log` files.
