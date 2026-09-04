---
name: tig-generate-co-registration
description: Generate a corrected-pointing navigation table (pointing.nav) plus tiepoint and overlap products for a set of overlapping rover frames with demo-co-registration.sh (marschkovl -> marsautotie -> marsnav, optionally marsnav2). Use when asked to co-register, align or tie frames, fix pointing before mosaicking, or produce tiepoints / a nav table.
---

# Generate a co-registration (pointing) solution

Script: `demo-co-registration.sh` (run from the repo root, writes to
`workspace-coreg/`). Reference: `docs/demos/co-registration.md`. Complete
`tig-setup` first.

MARS co-registration corrects **pointing**, it does not resample images. The
product is an XML navigation table that `marsmap`/`marsmos`/`marsortho` consume
via `navtable=`; the input images are untouched.

## Choose frames

- 2 to 200 frames from the **same site/drive** (same `N0xxxxxx` counter in the
  filename) with real overlap and initial pointing good enough for the matcher
  (`search=199` px default) to find it.
- Frames must be radiometrically usable by the calibration on
  `MARS_CONFIG_PATH` (same mission).
- MSL sample: five `~/visor_data/sample_data/CylindricalMosaic/NLB_*NCAM00293*.IMG`
  frames with `msl` calibration give ~26 tiepoints and a mean pixel error of
  ~6.2 -> ~2.7. For M20, any single-site NavCam sequence with adjacent
  azimuths works.

## Run

```bash
export MARS_CONFIG_PATH=~/.mars_calib/msl
./demo-co-registration.sh ~/visor_data/sample_data/CylindricalMosaic/NLB_*NCAM00293*.IMG
# or from a list file (one host path per line), adding a marsnav2 bundle adjustment
./demo-co-registration.sh --list frames.lis --nav2
```

Options: `--overlap PCT` (marschkovl acceptance, default 40), `--density N`
(marsautotie minimum spacing in px; **lower = more tiepoints**, default 50),
`--grid-spacing N` (candidate grid, default 15; raise for large frames when
marsautotie aborts on >300 candidates per axis), `--max-residual PX` (marsnav
outlier cut, default 10), `--solution-id ID` (written into the nav table,
default `COREG`), `--nav2`.

The script converts `--list`/argument paths to container-visible paths itself
(`readlink -f`, `/host` prefix for paths outside `$HOME`) and writes them to
`frames.lis`. Stages it runs, for re-running by hand from `workspace-coreg/`:

```bash
tig marschkovl inp=frames.lis out=\( overlap_left.lis overlap_right.lis \) overlap=40
tig marsautotie inp=frames.lis out=tiepoints.tpt density=50 grid_spacing=15
tig marsnav inp=frames.lis out=pointing.nav in_tpt=tiepoints.tpt \
  out_tpt=tiepoints_kept.tpt out_solution_id=COREG -remove max_residual=10 max_remove=50
tig marsnav2 inp=frames.lis out=pointing_nav2.nav in_tpt=tiepoints.tpt \
  out_tpt=tiepoints_nav2.tpt out_solution_id=COREG           # --nav2 only
```

Each program's full output is kept in `marschkovl.log`, `marsautotie.log`,
`marsnav.log` (`marsnav2.log`).

## Outputs (`workspace-coreg/`)

| File | What | Sanity check |
| --- | --- | --- |
| `pointing.nav` | XML navigation table, corrected pointing per frame, tagged with solution id `COREG` | non-empty XML mentioning `COREG`; `marsnav.log` shows `Final solution mean pixel error` well below `Commanded mean pixel error` (order 1-3 px for a well-tied set) |
| `tiepoints.tpt` | All tiepoints from marsautotie | `grep -c '<tie ' tiepoints.tpt` > 0; more than a handful per overlapping pair |
| `tiepoints_kept.tpt` | Tiepoints surviving `-remove` | most of `tiepoints.tpt` kept; losing most means the matcher, not the solver, failed |
| `overlap_left.lis`, `overlap_right.lis` | Parallel lists of pairs at or above `--overlap` | informational only - `marsautotie` ties every pair in `frames.lis` regardless. `marschkovl.log` prints the % for every pair; the MSL sample NCAM00293 frames sit at 31-33 %, so at the default 40 the lists are empty yet 25 tiepoints and a 6.0 -> 2.7 px solve still result |
| `pointing_nav2.nav`, `tiepoints_nav2.tpt` | Bundle-adjusted alternative (`--nav2`) | `marsnav2.log` reports no disconnected image groups |
| `frames.lis` | Input list, container paths | |

Verify a frame is actually constrained: `marsnav.log` must not say
`Input image N not represented by tiepoints` for it - an untied frame gets a
meaningless "correction" (a 3165 deg elevation change has been observed).

## Use the product

```bash
cd workspace-coreg
tig marsmap inp=frames.lis out=mosaic.img navtable=pointing.nav projection=CYLINDRICAL -nogrid
tig marsmos inp=frames.lis out=mosaic.img navtable=pointing.nav
```

Compare against the same command without `navtable=` to see the seams close.
`tig marscheckcm inp=frame.img tol=0.001` cross-checks a frame's label camera
model against calibration + kinematics. The two-epoch change product
(`tig-generate-change-monitoring`) is this same solve over frames from two
epochs, followed by projection and differencing.

## Troubleshooting

- `marschkovl` accepts no pairs: not fatal by itself (see above). Frames truly
  do not overlap or are from different sites only if `marschkovl.log` shows
  0 % or `pointing test failed` for every pair; otherwise lower `--overlap` if
  you want the lists populated.
- `marsautotie` produces 0 tiepoints: overlap exists but scenes are featureless
  or initial pointing error exceeds `search`; try `--density 25`, or pass
  `surface=` / `navtable=` by hand.
- `marsautotie` aborts about grid size: raise `--grid-spacing` (e.g. 40 for
  5120-sample M20 labels).
- Residual barely improves: tiepoints are wrong (check a few in
  `tiepoints.tpt` against the frames) or frames were taken from different
  rover positions - pointing correction cannot fix parallax; that needs the
  XYZ/ortho path.
- `marsnav2` failure is reported as a warning and does not invalidate
  `pointing.nav`.
