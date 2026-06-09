# ZCam Stereo Mesh Generation Demo

**Date:** 2026-06-04  
**Status:** Approved for Implementation  
**Component:** terrain-intelligence-generator demo scripts

## Overview

Replace the existing NavCam quick demo (`demo-mesh-generation.sh`) with a full ZCam stereo correlation pipeline that generates production-quality meshes matching the reference output in `/home/han/m2020/data/mesh/`. This demonstrates the complete MARS stereo processing workflow from raw ZCam stereo pair to multi-format 3D mesh outputs.

## Goals

1. **Match Reference Quality:** Generate mesh output identical to reference (227,623 vertices, 447,135 faces)
2. **Full Pipeline:** Demonstrate complete stereo correlation workflow (marsxyz → marsmesh → format conversions)
3. **Multiple Formats:** Produce OBJ, GLB, IV, and HT formats for various visualization tools
4. **Production Workflow:** Show realistic processing time and quality (not optimized for speed)

## Background

Current demo uses pre-computed NavCam XYZ point cloud from VISOR samples, completing in ~90 seconds. This avoids the time-consuming stereo correlation step but doesn't demonstrate the full MARS terrain reconstruction pipeline.

New ZCam data provides:
- **Source:** `/home/han/m2020/data/ZLF_*.VIC` and `ZRF_*.VIC` (16-bit VICAR stereo pair)
- **Reference mesh:** `/home/han/m2020/data/mesh/*.obj` (52MB, 227K vertices, 447K faces)
- **Additional formats:** GLB (9.9MB), IV (24MB), HT (9.7MB) for validation

## Design

### Pipeline Architecture

Four-stage pipeline matching MARS IDS production workflow:

```
Stage 1: Stereo Correlation (marsxyz)
  ZLF + ZRF stereo pair → XYZ point cloud
  Runtime: 10-15 minutes

Stage 2: Mesh Generation (marsmesh)  
  XYZ point cloud → OBJ mesh with texture
  Runtime: ~2 minutes

Stage 3: Format Conversion
  OBJ → GLB (obj2gltf VICAR tool)
  OBJ → IV (marsmesh parameter or separate tool)
  XYZ → HT (MARS height tool)
  Runtime: ~1 minute

Stage 4: Validation
  Compare vertex/face counts to reference
  Verify all formats generated successfully
```

**Total runtime:** 15-20 minutes (acceptable for production-quality demo)

### Input Data Handling

**Source files:**
- Left: `/home/han/m2020/data/ZLF_1868_0832768910_364RAS_N0881214ZCAM09921_1100LMJ01.VIC`
- Right: `/home/han/m2020/data/ZRF_1868_0832768910_364RAS_N0881214ZCAM09921_1100LMJ01.VIC`
- Format: 16-bit VICAR HALFWORD images (12MB each)

**Mount configuration:**
```bash
docker run -d \
  -v "/home/han/m2020/data:/m2020_data:ro,Z" \
  -v "$WORKSPACE:/workspace:Z" \
  -v "$CALIB_DIR:/usr/local/vicar/mars_calib:ro,Z" \
  "$IMAGE" tail -f /dev/null
```

**File staging in container:**
```bash
cp /m2020_data/ZLF_*.VIC left_image.vic
cp /m2020_data/ZRF_*.VIC right_image.vic
```

This keeps original data untouched and provides clean working names in the workspace.

### MARS Tool Invocations

#### Stage 1: Stereo Correlation

**Command:**
```bash
export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib
marsxyz inp="(left_image.vic, right_image.vic)" \
  out=pointcloud.xyz \
  out_disp=disparity.vic
```

**Key parameters:**
- No explicit subsampling (full resolution to match reference vertex count)
- Camera models auto-discovered from `MARS_CONFIG_PATH`
- Output: 3-band REAL format (X, Y, Z coordinates)
- Disparity map output for debugging if needed

**Expected runtime:** 10-15 minutes (full-resolution stereo correlation)

**Output validation:**
- Check `pointcloud.xyz` file size (should be comparable to reference processing)
- Verify VICAR label shows 3 bands, REAL format

#### Stage 2: Mesh Generation

**Command:**
```bash
marsmesh inp=pointcloud.xyz \
  out=terrain.obj \
  in_skin=right_image.vic \
  maxgap=5
```

**Key parameters:**
- `maxgap=5`: Maximum gap for triangle connection (controls mesh density)
- No explicit x/y subsampling to preserve reference quality
- Texture from right image (reference filename suggests ZRF right image used)
- Output: OBJ format with accompanying MTL material file

**Parameter tuning strategy:**
- Start with conservative `maxgap=5`
- Compare vertex count to reference (227,623)
- If mismatch >5%, adjust maxgap or investigate reference parameters
- Expect marsmesh to auto-detect optimal triangulation from point density

**Expected runtime:** ~2 minutes

**Output validation:**
- Verify `terrain.obj` and `terrain.mtl` files created
- Check vertex count: `grep "^v " terrain.obj | wc -l` → target ~227,623
- Check face count: `grep "^f " terrain.obj | wc -l` → target ~447,135

### Format Conversions

#### GLB (glTF Binary) - 9.9MB

**Tool:** VICAR `obj2gltf` (confirmed available at `/usr/local/vicar/dev/p2/lib/x86-64-linx/obj2gltf`)

**Command:**
```bash
obj2gltf inp=terrain.obj out=terrain.glb
```

**Validation:**
- File exists and size ~9-11MB
- glTF binary format header present: `file terrain.glb | grep "glTF binary"`

#### IV (Open Inventor 2.0) - 24MB

**Tool:** Check marsmesh parameters for direct IV generation

**Investigation needed:**
1. Run marsmesh without parameters to see full parameter list
2. Check for `OUT_IV` or `-format IV` parameter
3. If not available, identify separate VICAR/MARS tool for OBJ→IV conversion

**Expected command (if marsmesh supports):**
```bash
marsmesh inp=pointcloud.xyz out=terrain.obj out_iv=terrain.iv ...
```

**Or separate conversion:**
```bash
# Tool TBD - check VICAR dev/p2/lib for iv conversion utilities
```

**Validation:**
- File exists and size ~20-25MB
- Open Inventor format header: `file terrain.iv | grep "Open Inventor"`

#### HT (VICAR Height Map) - 9.7MB

**Tool:** Likely `marsmap` or separate MARS height projection tool

**Expected command:**
```bash
marsmap inp=pointcloud.xyz out=terrain.ht
```

**Format:** VICAR REAL32 (32-bit float elevation data)

**Validation:**
- File exists and size ~9-10MB  
- VICAR format header: `file terrain.ht | grep "VICAR"`
- 32-bit REAL format in label

**Note:** IV and HT tool commands will be confirmed during implementation by:
1. Checking marsmesh PDF documentation in container (`/usr/local/vicar/dev/mars/lib/x86-64-linx/marsmesh.pdf`)
2. Running marsmesh with no parameters to see full help
3. Searching VICAR bin directories for related tools

### Validation and Error Handling

#### Success Validation

After complete pipeline, validate output against reference:

**Vertex Count:**
```bash
VERTEX_COUNT=$(grep "^v " terrain.obj | wc -l)
REFERENCE_VERTICES=227623
DIFF_PCT=$(echo "scale=2; ($VERTEX_COUNT - $REFERENCE_VERTICES) * 100 / $REFERENCE_VERTICES" | bc)
```

**Face Count:**
```bash
FACE_COUNT=$(grep "^f " terrain.obj | wc -l)
REFERENCE_FACES=447135
```

**Acceptance criteria:**
- Vertex count within ±5% of reference (216,242 to 238,904)
- Face count within ±5% of reference (424,778 to 469,492)
- All four formats generated successfully

**File Size Validation:**
```
Format | Reference | Acceptable Range
-------|-----------|------------------
OBJ    | 52MB      | 45-60MB
GLB    | 9.9MB     | 8-12MB
IV     | 24MB      | 20-28MB
HT     | 9.7MB     | 8-12MB
```

Warnings (not failures) if outside ranges - sizes depend on compression and exact vertex count.

#### Progress Reporting

Display clear progress for long operations:

```
=== ZCam Stereo Mesh Generation Demo ===

Step 1: Copying ZCam stereo pair...
  Left:  ZLF_1868_0832768910_364RAS_N0881214ZCAM09921_1100LMJ01.VIC (12MB)
  Right: ZRF_1868_0832768910_364RAS_N0881214ZCAM09921_1100LMJ01.VIC (12MB)
✓ Files copied

Step 2: Running stereo correlation (marsxyz)...
  This takes 10-15 minutes for full-resolution processing...
  [Progress indicators if available from marsxyz]
✓ XYZ point cloud generated: pointcloud.xyz

Step 3: Generating mesh (marsmesh)...
  This takes ~2 minutes...
✓ Mesh generated: terrain.obj (vertices: 228,456, faces: 448,901)

Step 4: Converting to additional formats...
  GLB (glTF binary)...      ✓ terrain.glb (9.8MB)
  IV (Open Inventor)...     ✓ terrain.iv (23.9MB)
  HT (Height map)...        ✓ terrain.ht (9.6MB)

Step 5: Validation
  Reference vs Generated:
    Vertices: 227,623 vs 228,456 (+0.4%)  ✓ Within tolerance
    Faces:    447,135 vs 448,901 (+0.4%)  ✓ Within tolerance
    Formats:  ✓ OBJ, ✓ GLB, ✓ IV, ✓ HT

=== Demo Complete ===
Total time: 18m 23s

Generated files in workspace/:
  - left_image.vic      : Left ZCam image
  - right_image.vic     : Right ZCam image
  - pointcloud.xyz      : XYZ point cloud (stereo correlation output)
  - disparity.vic       : Disparity map
  - terrain.obj         : 3D mesh (Wavefront OBJ)
  - terrain.mtl         : Material file
  - terrain.glb         : glTF binary mesh
  - terrain.iv          : Open Inventor mesh
  - terrain.ht          : VICAR height map

To view the mesh:
  - Blender: File → Import → Wavefront (.obj) or glTF (.glb)
  - MeshLab: File → Import Mesh → terrain.obj
  - CloudCompare: File → Open → terrain.obj
  - Online: Upload to https://3dviewer.net/
```

#### Error Handling

**Missing calibration:**
```bash
if [ ! -d "/usr/local/vicar/mars_calib" ]; then
  echo "ERROR: MARS calibration not mounted"
  echo "  Set MARS_CONFIG_PATH and restart container"
  exit 1
fi
```

**MARS tool failures:**
```bash
if ! marsxyz ...; then
  echo "ERROR: marsxyz stereo correlation failed"
  echo "Check calibration files and input image compatibility"
  docker logs "$CONTAINER" | tail -50
  exit 1
fi
```

**Vertex count mismatch (warning, not failure):**
```bash
if [ $DIFF_PCT -gt 5 ] || [ $DIFF_PCT -lt -5 ]; then
  echo "WARNING: Vertex count differs from reference by ${DIFF_PCT}%"
  echo "  Reference: 227,623"
  echo "  Generated: $VERTEX_COUNT"
  echo "  This may indicate different marsxyz/marsmesh parameters"
fi
```

**Missing output files:**
```bash
for file in terrain.obj terrain.glb terrain.iv terrain.ht; do
  if [ ! -f "/workspace/$file" ]; then
    echo "ERROR: Expected output missing: $file"
    exit 1
  fi
done
```

### Script Structure

Replace `demo-mesh-generation.sh` with updated structure:

```bash
#!/bin/bash
set -e

# Configuration
IMAGE="ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource"
CONTAINER="tig-mesh-demo"
WORKSPACE="$(pwd)/workspace"
M2020_DATA="/home/han/m2020/data"

# Find calibration (reuse existing helper)
source find-calibration.sh
CALIB_DIR=$(find_calibration)

# Validate inputs
validate_prerequisites() {
  # Check M2020 data exists
  # Check calibration exists
  # Check Docker available
}

# Start container with all mounts
start_container() {
  docker run -d --name "$CONTAINER" \
    -v "$WORKSPACE:/workspace:Z" \
    -v "$M2020_DATA:/m2020_data:ro,Z" \
    -v "$CALIB_DIR:/usr/local/vicar/mars_calib:ro,Z" \
    "$IMAGE" tail -f /dev/null
}

# Stage 1: Copy input files
stage_input_files() {
  docker exec "$CONTAINER" bash -c '
    cp /m2020_data/ZLF_*.VIC /workspace/left_image.vic
    cp /m2020_data/ZRF_*.VIC /workspace/right_image.vic
  '
}

# Stage 2: Stereo correlation
run_stereo_correlation() {
  echo "Running marsxyz stereo correlation (10-15 minutes)..."
  docker exec "$CONTAINER" bash -c '
    cd /workspace
    export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib
    marsxyz inp="(left_image.vic, right_image.vic)" \
      out=pointcloud.xyz \
      out_disp=disparity.vic
  '
}

# Stage 3: Mesh generation
generate_mesh() {
  echo "Generating mesh with marsmesh (~2 minutes)..."
  docker exec "$CONTAINER" bash -c '
    cd /workspace
    export MARS_CONFIG_PATH=/usr/local/vicar/mars_calib
    marsmesh inp=pointcloud.xyz \
      out=terrain.obj \
      in_skin=right_image.vic \
      maxgap=5
  '
}

# Stage 4: Format conversions
convert_formats() {
  # GLB conversion
  docker exec "$CONTAINER" bash -c '
    cd /workspace
    obj2gltf inp=terrain.obj out=terrain.glb
  '
  
  # IV conversion (command TBD during implementation)
  convert_to_iv
  
  # HT conversion (command TBD during implementation)
  generate_height_map
}

# Stage 5: Validation
validate_output() {
  # Count vertices and faces
  # Compare to reference
  # Check file sizes
  # Display summary table
}

# Main execution
main() {
  echo "=== ZCam Stereo Mesh Generation Demo ==="
  validate_prerequisites
  start_container
  stage_input_files
  run_stereo_correlation
  generate_mesh
  convert_formats
  validate_output
  echo "=== Demo Complete ==="
}

main
```

## Implementation Notes

### Tool Parameter Discovery

During implementation, confirm commands for IV and HT generation:

1. **Check marsmesh documentation:**
   ```bash
   docker exec "$CONTAINER" cat /usr/local/vicar/dev/mars/lib/x86-64-linx/marsmesh.pdf
   ```

2. **List marsmesh parameters:**
   ```bash
   docker exec "$CONTAINER" bash -c 'cd /workspace && marsmesh' 2>&1 | less
   ```

3. **Search for conversion tools:**
   ```bash
   docker exec "$CONTAINER" find /usr/local/vicar/dev -name "*iv*" -o -name "*height*"
   ```

### Reference Mesh Analysis

If needed to understand reference generation parameters:

1. **Parse OBJ for metadata comments:**
   ```bash
   head -100 /home/han/m2020/data/mesh/*.obj | grep "^#"
   ```

2. **Check for VICAR label files:**
   ```bash
   ls /home/han/m2020/data/mesh/*.lbl
   ```

3. **Compare file structures:**
   ```bash
   diff <(head -50 reference.obj) <(head -50 terrain.obj)
   ```

### Texture Handling

Reference mesh uses right image (ZRF) based on filename. Confirm texture selection:
- Try `in_skin=right_image.vic` first (matches reference naming)
- If texture quality differs, test with left image
- Compare texture coordinate ranges in OBJ files

## Success Criteria

1. **Mesh Quality:** Vertex count within ±5% of reference (227,623 ± 11,381)
2. **Face Count:** Face count within ±5% of reference (447,135 ± 22,357)
3. **Format Coverage:** All four formats generated successfully (OBJ, GLB, IV, HT)
4. **File Sizes:** Within reasonable ranges (±20% of reference sizes)
5. **Documentation:** Clear progress output, timing information, validation summary
6. **Error Handling:** Graceful failures with actionable error messages
7. **Runtime:** Complete pipeline in 15-25 minutes (acceptable for production demo)

## Non-Goals

- **Speed optimization:** Not using aggressive subsampling for fast demo
- **Parameter auto-tuning:** Not implementing iterative parameter adjustment
- **Multiple datasets:** Demo works with specific ZCam pair only
- **Texture conversion:** Not converting texture to PNG (focus on mesh formats)
- **Legacy NavCam demo:** Not preserving quick NavCam workflow

## Future Enhancements

1. **Dataset selection:** Make demo work with any stereo pair (detect file patterns)
2. **Parameter presets:** Add fast/balanced/quality modes
3. **Parallel demos:** Restore NavCam quick demo alongside full ZCam demo
4. **Texture optimization:** Add texture format conversions and quality controls
5. **Comparison visualization:** Generate side-by-side reference vs generated mesh images

## Dependencies

**Required:**
- terrain-intelligence-generator Docker image (opensource or newer)
- M2020 calibration files at `/home/han/m2020/data/mars_calibration_m20/` or detected location
- ZCam stereo pair at `/home/han/m2020/data/ZLF_*.VIC` and `ZRF_*.VIC`
- Reference mesh at `/home/han/m2020/data/mesh/` for validation

**Tools confirmed available:**
- `marsxyz` - Stereo correlation
- `marsmesh` - Mesh generation  
- `obj2gltf` - OBJ to glTF conversion

**Tools to be confirmed:**
- IV generation tool (marsmesh parameter or separate tool)
- HT generation tool (marsmap or similar)

## Summary

This design replaces the existing quick NavCam demo with a production-quality ZCam stereo mesh generation pipeline that demonstrates the full MARS terrain reconstruction workflow. The demo generates mesh output matching the reference quality (227K vertices, 447K faces) in four formats (OBJ, GLB, IV, HT) with comprehensive validation and error handling. Processing time of 15-20 minutes is acceptable for demonstrating realistic MARS production workflows.
