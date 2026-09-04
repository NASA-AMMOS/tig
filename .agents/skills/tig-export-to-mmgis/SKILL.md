---
name: tig-export-to-mmgis
description: Turn TIG products into MMGIS layers and register them - a vertical panorama mosaic into a mercator TMS tile layer and a terrain mesh into a GLB model layer, via examples/mmgis-integration/tig-to-mmgis.sh, docker compose, and register-layers.sh. Use when asked to put a TIG mosaic or mesh on a map, into MMGIS, or to produce map tiles / glTF from TIG outputs.
---

# Export TIG products to MMGIS

Directory: `examples/mmgis-integration/` (run its scripts from there).
Reference: its `README.md`. Complete `tig-setup` first; GDAL >= 3.4
(`gdal_translate`, `gdal2tiles.py`), `python3`, `curl` and Docker Compose are
also needed.

| TIG product | MMGIS layer | Pipeline |
| --- | --- | --- |
| `workspace/panorama.img` from `tig-generate-panorama-mosaic` with `--projection vertical` | `tile` | `vicario` -> PNG -> `gdal_translate` GeoTIFF -> `gdal2tiles.py` mercator TMS `{z}/{x}/{y}.png` |
| `workspace/terrain.obj` (+ `texture.png`) from `tig-generate-terrain-mesh` | `model` (globe only) | SITE frame rotated to the model frame -> `obj2gltf` GLB, `KHR_materials_unlit` patch, gamma-2.2 texture |

## 1. Inputs

- The mosaic label must be `MAP_PROJECTION_TYPE='VERTICAL'`; the export refuses
  cylindrical/polar mosaics. Follow the vertical section of
  `tig-generate-panorama-mosaic`: extents are SITE-frame metres centred on the
  rover's SITE x, y (not `-30..30` unless the rover is at the site origin), and
  the projection plane must go through the rover (`surf_coord=ROVER`) or the
  imagery is smeared outward.
- The mesh needs `texture.png` beside `terrain.obj` (or `--texture FILE`).
- **Site coordinates are mandatory and not in any TIG product**: `marsmap` and
  `marsmesh` write metres in the rover `SITE_FRAME` (+X north, +Y east, +Z
  down). The export adds the label's `X_AXIS_*`/`Y_AXIS_*` extents (and the
  mesh vertices) to `--site-lon/--site-lat`, so those must be the planetary
  position of the **SITE frame origin**, not of the rover - if you only know
  the rover's lon/lat, subtract its `ROVER_NAV_FRAME` `ORIGIN_OFFSET_VECTOR`
  (metres north, east) first. Get positions from the mission's localization
  products (PDS `RVER`/localization tables, or MMGIS rover-position layers).
  Only one of `--mosaic`/`--mesh` is required.

## 2. Export layers

```bash
cd examples/mmgis-integration
./tig-to-mmgis.sh \
    --mosaic ../../workspace/panorama.img \
    --mesh   ../../workspace/terrain.obj \
    --site-lon 137.4417 --site-lat -4.5895
```

Options: `--mesh-elev M` (0; only useful with a matching terrain layer),
`--texture FILE`, `--texture-gamma G` (2.2; `1` disables), `--mission NAME`
(`TIG-Demo`), `--missions-dir DIR` (`./Missions`), `--mosaic-layer` /
`--mesh-layer` names, `--radius M` (Mars equatorial radius for metres ->
degrees).

Outputs under `Missions/TIG-Demo/`:

| Path | Check |
| --- | --- |
| `Layers/<mosaic layer>/{z}/{x}/{y}.png` | tiles exist for a few zooms (e.g. 18-20 for a 60 m product); `find Layers -name '*.png' \| wc -l` > 0 |
| `Layers/<mesh layer>/*.glb` (+ OBJ/MTL/texture fallback) | GLB of several MB; texture PNG 8-bit |
| `<layer>.layer.json` (one per product) | `tile` entry has `tileformat: tms`, `boundingBox [west,south,east,north]`; `model` entry has `position.longitude/latitude` at the mesh centroid |

Two facts to keep straight when debugging: the pyramid must be **mercator**
(geodetic tiles 404 in MMGIS' Mars web-mercator CRS), and the intermediate
GeoTIFF is tagged `EPSG:4326` because PROJ rejects a custom Mars ellipsoid -
extents are still computed with the body radius.

## 3. Serve and register

```bash
cp env.example .env                  # set SECRET and DB_PASS
docker compose up -d                 # MMGIS 5.2.24 + PostGIS, mounts ./Missions
curl -s http://localhost:8888/api/utils/healthcheck
curl -X POST http://localhost:8888/api/users/first_signup \
    -H "Content-Type: application/json" \
    -d '{"username":"tigadmin","password":"<strong password>"}'   # once per fresh DB
./register-layers.sh --center-lon 137.4417 --center-lat -4.5895 --username tigadmin
```

`register-layers.sh` prompts for the password (`MMGIS_PASSWORD` or
`MMGIS_TOKEN` env also work; avoid `--password`), creates the mission, sets its
view and Mars radii, and `POST /addLayer`s every `*.layer.json`; re-running
updates rather than duplicates. Then open
`http://localhost:8888/?mission=TIG-Demo`: the mosaic draws in **Map**, the
mesh in **Globe** only.

## Troubleshooting

- `tig-to-mmgis.sh` rejects the mosaic: it is not a vertical projection;
  re-run the panorama demo with `--projection vertical`.
- Tiles fetch fine by hand but the map is blank: pyramid was built geodetic;
  rebuild with the script (mercator).
- Mesh renders almost black: the unlit/gamma fixes were bypassed. Note
  `obj2gltf` keeps `texture.png` as a relative URI, so a texture-only change
  leaves the GLB byte-identical - hard-reload the browser. Even when correct,
  the model renders dimmer than the same imagery as tiles.
- Mesh in the wrong place/orientation: `--site-lon/--site-lat` wrong, or the
  SITE +X is not true north - put the difference in the layer's `rotation.y`.
- Registration 401/403: no admin session; do `first_signup` once, or pass a
  long-term token (`period` is in **milliseconds**, e.g. `86400000`).
- Deleting a mission in Configure renames `Missions/<mission>` to
  `<mission>_deleted_`; rename back or re-export before re-registering.
- `gdal2tiles.py` prints an `AttributeError: _ARRAY_API not found` traceback
  (Ubuntu `python3-gdal` built against NumPy 1.x with NumPy 2 installed): it
  is a failed optional import, not a failure - tiles are still written and the
  script exits 0; confirm with `find Layers/<name> -name '*.png' | wc -l`.
- No GPU: Chrome needs `--use-angle=swiftshader-webgl` for the Globe.
- Only the MSL path has been run end to end; the export is not
  mission-specific but M20 products were not exercised.
