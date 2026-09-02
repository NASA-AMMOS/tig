#!/bin/bash
#
# test-release-regression.sh - Release-gated visual regression suite
#
# test-docker-image.sh proves the image is wired up.  test-product-pipeline.sh
# proves the programs produce terrain products from a synthetic fixture.  This
# script is the release sibling of both: it runs the shipped demo pipelines on
# REAL mission frames, asserts on the content of every product, and collects a
# PNG per stage plus a report.md so a release can be signed off by looking at
# the images.
#
# Data: the public VICAR 5.0 VISOR sample data (MSL Navcam, sol 1000-ish) and
# the MSL VISOR calibration, both pinned below.  Nothing is downloaded unless
# --download is given, and missing data is a hard failure, never a skip.
#
# Coverage (each stage: one machine assertion + one PNG):
#   radiometric-correction  marsrad frames from the panorama run
#   cylindrical-mosaic      demo-panorama-mosaic.sh --auto-extent
#   polar-mosaic            demo-panorama-mosaic.sh --projection polar
#   stereo-xyz              marscorr -> marscor3 -> marsxyz on a Navcam pair
#   mesh                    demo-mesh-generation-with-xyz.sh --xyz
#   surface-characteristics demo-surface-characteristics.sh
#   co-registration         demo-co-registration.sh + residual difference raster
#   change-monitoring       demo-change-monitoring.sh on two frames of one sweep,
#                           windowed to their overlap; see CHANGE_BOUNDS below
#
# Not covered, and reported as UNVERIFIED rather than skipped:
#   demo stereo path        demo-mesh-generation-with-xyz.sh --stereo-left/right
#                           uses marscorr's default seed, which does not
#                           correlate these frames; see STEREO_SEED below
#
# Usage:
#   ./test-release-regression.sh [image-tag] [options]
#
#   --data-dir DIR      VISOR data root (default $VISOR_DATA_DIR or ~/visor_data)
#   --calibration DIR   mission calibration dir (default DATA_DIR/calibration/msl;
#                       not combinable with --download)
#   --out-dir DIR       report + PNG output (default ./release-regression-<stamp>)
#   --download          fetch the pinned VICAR 5.0 archives into DATA_DIR first
#   --keep              keep the per-stage scratch directories
#
# Example:
#   ./test-release-regression.sh ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource
#
# Runtime: ~8 minutes, dominated by the ~6 minute full-frame marscorr.
# Download cost: 740 MB sample data + 380 MB MSL calibration (1.8 GB on disk).

# No 'set -e': every stage records its own result and the summary exits 1.
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_TAG="ghcr.io/nasa-ammos/tig/terrain-intelligence-generator:opensource"
DATA_DIR="${VISOR_DATA_DIR:-${HOME}/visor_data}"
CALIB_DIR=""
OUT_DIR=""
DO_DOWNLOAD=0
KEEP_SCRATCH=0

while [ $# -gt 0 ]; do
    case "$1" in
        --data-dir)     DATA_DIR="$2"; shift 2 ;;
        --calibration)  CALIB_DIR="$2"; shift 2 ;;
        --out-dir)      OUT_DIR="$2"; shift 2 ;;
        --download)     DO_DOWNLOAD=1; shift ;;
        --keep)         KEEP_SCRATCH=1; shift ;;
        -h|--help)      sed -n '/^# Usage:/,/^# Download cost/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)             echo "unknown option: $1" >&2; exit 1 ;;
        *)              IMAGE_TAG="$1"; shift ;;
    esac
done

# The archive dictates its own layout, so --download cannot fill a custom dir.
if [ -n "${CALIB_DIR}" ] && [ "${DO_DOWNLOAD}" -eq 1 ]; then
    echo "--download extracts to DATA_DIR/calibration/msl; drop --calibration or --download" >&2
    exit 1
fi
CALIB_DIR="${CALIB_DIR:-${DATA_DIR}/calibration/msl}"
OUT_DIR="${OUT_DIR:-${PWD}/release-regression-$(date +%Y%m%d-%H%M%S)}"

# Absolutise: each stage runs its demo from its own scratch directory, where a
# relative path off the caller's cwd would no longer resolve.
abs_path() { case "$1" in /*) echo "$1" ;; *) echo "${PWD%/}/${1#./}" ;; esac; }
DATA_DIR="$(abs_path "${DATA_DIR}")"
CALIB_DIR="$(abs_path "${CALIB_DIR}")"
OUT_DIR="$(abs_path "${OUT_DIR}")"
SAMPLE_DIR="${DATA_DIR}/sample_data"
IMAGE_DIR="${OUT_DIR}/images"
SCRATCH="${OUT_DIR}/scratch"
REPORT="${OUT_DIR}/report.md"

# Pinned public data (docs/demos/downloading-visor-data.md).
SAMPLE_URL="https://github.com/NASA-AMMOS/VICAR/releases/download/5.0/visor_sample_data_20230623.tar.gz"
CALIB_URL="https://github.com/NASA-AMMOS/VICAR/releases/download/5.0/visor_calibration_20230608_msl.tar.gz"

# Frames, all from the pinned sample data.  The five NCAM00293 left frames are
# one Navcam sweep from a single site/drive, so they mosaic and co-register.
PANO_SEQ=(NLB_712299508 NLB_712299539 NLB_712299570 NLB_712299596 NLB_712299621)
PANO_SUFFIX="ILT_F0961766NCAM00293M1.IMG"
PANO_SRC="${SAMPLE_DIR}/CylindricalMosaic"
STEREO_L="${SAMPLE_DIR}/CylperMosaic/NLB_712299404ILT_F0961766NCAM00353M1.IMG"
STEREO_R="${SAMPLE_DIR}/CylperMosaic/NRB_712299404ILT_F0961766NCAM00353M1.IMG"
SURFACE_XYZ="${SAMPLE_DIR}/Roughness/NLB_712299404XYZLF0961766NCAM00353M1.IMG"

# marscorr's default seed (124,127,126,108) fails on these full Navcam frames
# ("No valid seed points found"); the frame centre correlates, so seed there.
STEREO_SEED="512,512,512,512"

# Floors and bounds.  Every number is the observed value from the reference run
# recorded in the PR, loosened so a working chain passes and a degenerate or
# empty product fails.  Observed values are in the trailing comments.
MIN_RAD_STD=100             # rad frame std 552
MIN_CYL_LINES=800           # 1217
MIN_CYL_SAMPLES=2500        # 3686
MIN_CYL_STD=200             # 986
MIN_POLAR_DIM=3000          # 5131 x 5131
MIN_POLAR_STD=200           # 781
MIN_DISPARITY_STD=10        # 267
MIN_XYZ_POINTS=5000         # 11382
MIN_VERTICES=10000          # 45759
MIN_FACES=8000              # 38680
MAX_SLOPE_DEG=180           # max 118.96 (overhangs exceed 90)
MIN_SLOPE_STD=1             # 12.50
MAX_ROUGHNESS_M=1.0         # max 0.100, mean 0.055
# marsrough writes 0.1 where it cannot compute, so an all-sentinel raster is
# flat: a spread floor is what separates it from a real product (observed 0.043).
MIN_ROUGH_STD=0.005
MIN_TIEPOINTS=10            # 25
MAX_COREG_RESIDUAL_PX=5.0   # 5.96 commanded -> 2.66 solved
# The two change epochs are single frames 29.7 deg apart in azimuth, so their
# joint projection is mostly unpainted: pin the window to their common ground.
CHANGE_OVERLAP=30           # marschkovl measures 31.0% for this pair
CHANGE_BOUNDS="75 95 5 -30" # inside both footprints (joint 42.6..130.0 az, 15.0..-40.1 el)
MAX_COREG_DIFF_MEAN=5.0     # 0.00005 DN, std 0.138

STAGES_PASSED=0
STAGES_FAILED=0
STAGES_UNVERIFIED=0
declare -a ROWS=()

hard_fail() {
    echo -e "${RED}✗ FATAL: $1${NC}" >&2
    shift
    for line in "$@"; do echo "  $line" >&2; done
    exit 2
}

banner() {
    echo ""
    echo "============================================"
    echo "$1"
    echo "============================================"
}

# row: name | PASS/FAIL/UNVERIFIED | evidence | png (relative, may be empty)
record() {
    local status="$1" name="$2" detail="$3" png="${4:-}"
    ROWS+=("${name}|${status}|${detail}|${png}")
    case "${status}" in
        PASS)       STAGES_PASSED=$((STAGES_PASSED + 1)); echo -e "${GREEN}✓ ${name}: ${detail}${NC}" ;;
        FAIL)       STAGES_FAILED=$((STAGES_FAILED + 1)); echo -e "${RED}✗ ${name}: ${detail}${NC}" ;;
        UNVERIFIED) STAGES_UNVERIFIED=$((STAGES_UNVERIFIED + 1)); echo -e "${YELLOW}○ ${name}: ${detail}${NC}" ;;
    esac
}

# Numeric comparison without bc: awk exits 0 when the expression holds.
ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 >= b+0)}'; }
le() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 <= b+0)}'; }

# "mean std min max" from hist, "lines samples bands" from label.
vic_stat() {
    local dir; dir="$(dirname "$1")"
    (cd "${dir}" && tig hist "$(basename "$1")" 2>/dev/null) | awk -F= '
        /AVERAGE GRAY LEVEL/ {mean=$2} /STANDARD DEVIATION/ {std=$2}
        /MIN\. DN/ {min=$2} /MAX\. DN/ {max=$2}
        END {printf "%s %s %s %s\n", mean+0, std+0, min+0, max+0}'
}

vic_dims() {
    local dir; dir="$(dirname "$1")"
    (cd "${dir}" && tig label -list "$(basename "$1")" 2>/dev/null) | awk '
        /lines per band/ {l=$1} /samples per line/ {s=$1} /bands$/ {b=$1}
        END {printf "%s %s %s\n", l+0, s+0, b+0}'
}

# Stretch one band to a byte PNG in IMAGE_DIR.
make_png() {
    local inp="$1" name="$2" lo="$3" hi="$4" band="${5:-1}"
    local dir; dir="$(dirname "$inp")"
    # Per-output temp names: a shared one would let a failed step convert the
    # previous stage's leftovers into this stage's PNG.
    ( cd "${dir}" || exit 1
      rm -f "png_band_${name}.vic" "png_byte_${name}.vic" "${name}.png"
      tig copy "$(basename "${inp}")" "png_band_${name}.vic" sb="${band}" nb=1 >/dev/null 2>&1
      tig cform "png_band_${name}.vic" "png_byte_${name}.vic" oform=byte irange=\("${lo}","${hi}"\) orange=\(0,255\) >/dev/null 2>&1
      tig vicario "png_byte_${name}.vic" "${name}.png" >/dev/null 2>&1 )
    [ -s "${dir}/${name}.png" ] && cp "${dir}/${name}.png" "${IMAGE_DIR}/${name}.png"
}

collect_png() {
    local src="$1" name="$2"
    [ -s "${src}" ] && cp "${src}" "${IMAGE_DIR}/${name}.png"
}

# --- preconditions ----------------------------------------------------------

banner "Release visual regression suite"
echo -e "${BLUE}image:       ${IMAGE_TAG}${NC}"
echo "data:        ${DATA_DIR}"
echo "calibration: ${CALIB_DIR}"
echo "output:      ${OUT_DIR}"

command -v tig >/dev/null 2>&1 || hard_fail "the tig CLI is not on PATH" \
    "install it from this repo: pip install ./tig-cli"
# Same resolution order as tig-cli's Runtime.detect, so a Podman or Finch host
# runs the suite too.
RUNTIME="${TIG_CONTAINER_RUNTIME:-}"
if [ -z "${RUNTIME}" ]; then
    for r in docker podman nerdctl finch; do
        command -v "${r}" >/dev/null 2>&1 && { RUNTIME="${r}"; break; }
    done
fi
command -v "${RUNTIME:-none}" >/dev/null 2>&1 || hard_fail \
    "no container runtime on PATH (tried docker, podman, nerdctl, finch)" \
    "install one, or set TIG_CONTAINER_RUNTIME to the command to use"
echo "runtime:     ${RUNTIME}"

# Fills MISSING with the input frames not on disk.  The download guards use it
# so a cancelled extraction, which still leaves the directory behind, is refetched.
missing_frames() {
    local f
    MISSING=()
    for f in "${STEREO_L}" "${STEREO_R}" "${SURFACE_XYZ}"; do
        [ -s "${f}" ] || MISSING+=("${f}")
    done
    for f in "${PANO_SEQ[@]}"; do
        [ -s "${PANO_SRC}/${f}${PANO_SUFFIX}" ] || MISSING+=("${PANO_SRC}/${f}${PANO_SUFFIX}")
    done
}

# Same requirement as find-calibration.sh's verify_calibration, so the demos
# cannot fail on calibration the suite already accepted.
calib_complete() {
    [ -n "$(ls -A "${CALIB_DIR}/camera_models" 2>/dev/null)" ] &&
        [ -n "$(ls -A "${CALIB_DIR}/param_files" 2>/dev/null)" ]
}

if [ "${DO_DOWNLOAD}" -eq 1 ]; then
    banner "Downloading pinned VICAR 5.0 VISOR data (~1.1 GB compressed)"
    # Without pipefail a truncated curl hides behind tar's exit status.
    set -o pipefail
    mkdir -p "${DATA_DIR}" || hard_fail "cannot create ${DATA_DIR}"
    missing_frames
    [ ${#MISSING[@]} -eq 0 ] || curl -fL "${SAMPLE_URL}" | tar -zxf - -C "${DATA_DIR}" \
        || hard_fail "sample data download failed: ${SAMPLE_URL}"
    # Both archives carry their own top-level dir, so they extract into DATA_DIR.
    calib_complete || curl -fL "${CALIB_URL}" | tar -zxf - -C "${DATA_DIR}" \
        || hard_fail "calibration download failed: ${CALIB_URL}"
    set +o pipefail
fi

calib_complete || hard_fail \
    "no complete MSL calibration at ${CALIB_DIR} (expected camera_models/ and param_files/)" \
    "re-run with --download, or fetch it manually:" \
    "  curl -L '${CALIB_URL}' | tar -zxf - -C '${DATA_DIR}'"

missing_frames
if [ ${#MISSING[@]} -gt 0 ]; then
    hard_fail "${#MISSING[@]} input frame(s) missing from ${SAMPLE_DIR}" \
        "${MISSING[@]}" \
        "re-run with --download, or fetch the sample data manually:" \
        "  curl -L '${SAMPLE_URL}' | tar -zxf - -C '${DATA_DIR}'"
fi

# Clear a reused output dir: a stale PNG or product would be reported as this
# run's, and the report claims every image came from this run.
rm -rf "${IMAGE_DIR}" "${SCRATCH}"
mkdir -p "${IMAGE_DIR}" "${SCRATCH}" || hard_fail "cannot create ${OUT_DIR}"
export MARS_CONFIG_PATH="${CALIB_DIR}"
export CONTAINER_IMAGE="${IMAGE_TAG}"

# Pull first: :opensource is a moving tag, so a stale local copy would be tested
# under the released tag's name.  Fall back to a local image when offline.
"${RUNTIME}" pull "${IMAGE_TAG}" >/dev/null 2>&1 || \
    "${RUNTIME}" image inspect "${IMAGE_TAG}" >/dev/null 2>&1 || \
    hard_fail "cannot pull ${IMAGE_TAG}"

PANO_FRAMES=()
for s in "${PANO_SEQ[@]}"; do PANO_FRAMES+=("${PANO_SRC}/${s}${PANO_SUFFIX}"); done

SUITE_START=$(date +%s)

# --- cylindrical mosaic + radiometric correction -----------------------------

banner "Stage: cylindrical mosaic (demo-panorama-mosaic.sh --auto-extent)"
CYL_WS="${SCRATCH}/cylindrical/workspace"
mkdir -p "${SCRATCH}/cylindrical"
( cd "${SCRATCH}/cylindrical" && "${REPO_ROOT}/demo-panorama-mosaic.sh" --auto-extent \
    "${PANO_FRAMES[@]}" ) > "${SCRATCH}/cylindrical/demo.log" 2>&1
CYL_RC=$?

if [ ${CYL_RC} -eq 0 ] && [ -s "${CYL_WS}/panorama.img" ]; then
    read -r CYL_L CYL_S _ <<<"$(vic_dims "${CYL_WS}/panorama.img")"
    read -r CYL_MEAN CYL_STD CYL_MIN CYL_MAX <<<"$(vic_stat "${CYL_WS}/panorama.img")"
    collect_png "${CYL_WS}/panorama.png" "cylindrical_mosaic"
    if [ "${CYL_L}" -ge ${MIN_CYL_LINES} ] && [ "${CYL_S}" -ge ${MIN_CYL_SAMPLES} ] \
       && ge "${CYL_STD}" ${MIN_CYL_STD} && ge "${CYL_MAX}" 1; then
        record PASS "cylindrical-mosaic" \
            "${CYL_L}x${CYL_S} mosaic, mean ${CYL_MEAN}, std ${CYL_STD}, range ${CYL_MIN}..${CYL_MAX} DN" \
            "images/cylindrical_mosaic.png"
    else
        record FAIL "cylindrical-mosaic" \
            "degenerate mosaic: ${CYL_L}x${CYL_S}, std ${CYL_STD} (need >=${MIN_CYL_LINES}x${MIN_CYL_SAMPLES}, std >=${MIN_CYL_STD})" \
            "images/cylindrical_mosaic.png"
    fi
else
    record FAIL "cylindrical-mosaic" "demo-panorama-mosaic.sh failed (rc=${CYL_RC}), see scratch/cylindrical/demo.log"
fi

banner "Stage: radiometric correction (marsrad frames from the mosaic run)"
RAD_FRAME=$(find "${CYL_WS}/panorama_rad" -name '*.rad.img' 2>/dev/null | sort | head -1)
RAD_COUNT=$(find "${CYL_WS}/panorama_rad" -name '*.rad.img' 2>/dev/null | wc -l)
if [ -n "${RAD_FRAME}" ] && [ "${RAD_COUNT}" -eq ${#PANO_FRAMES[@]} ]; then
    read -r RAD_L RAD_S _ <<<"$(vic_dims "${RAD_FRAME}")"
    read -r RAD_MEAN RAD_STD RAD_MIN RAD_MAX <<<"$(vic_stat "${RAD_FRAME}")"
    read -r RAW_MEAN _ _ _ <<<"$(vic_stat "${PANO_FRAMES[0]}")"
    make_png "${RAD_FRAME}" "radiometric_correction" "${RAD_MIN}" "${RAD_MAX}"
    # Radiometry must change the DN scale and keep scene contrast.
    if ge "${RAD_STD}" ${MIN_RAD_STD} && [ "${RAD_L}" -gt 0 ] \
       && awk -v a="${RAD_MEAN}" -v b="${RAW_MEAN}" 'BEGIN{exit !(a != b)}'; then
        record PASS "radiometric-correction" \
            "${RAD_COUNT} frames, ${RAD_L}x${RAD_S}, mean ${RAW_MEAN} DN raw -> ${RAD_MEAN} corrected, std ${RAD_STD}" \
            "images/radiometric_correction.png"
    else
        record FAIL "radiometric-correction" \
            "corrected frame is degenerate: mean ${RAD_MEAN}, std ${RAD_STD} (need std >=${MIN_RAD_STD} and a DN change)" \
            "images/radiometric_correction.png"
    fi
else
    record FAIL "radiometric-correction" \
        "expected ${#PANO_FRAMES[@]} marsrad frames in ${CYL_WS}/panorama_rad, found ${RAD_COUNT}"
fi

# --- polar mosaic -----------------------------------------------------------

banner "Stage: polar mosaic (demo-panorama-mosaic.sh --projection polar)"
POLAR_WS="${SCRATCH}/polar/workspace"
mkdir -p "${SCRATCH}/polar"
( cd "${SCRATCH}/polar" && "${REPO_ROOT}/demo-panorama-mosaic.sh" --projection polar \
    --top-el 30 "${PANO_FRAMES[@]}" ) > "${SCRATCH}/polar/demo.log" 2>&1
POLAR_RC=$?

if [ ${POLAR_RC} -eq 0 ] && [ -s "${POLAR_WS}/panorama.img" ]; then
    read -r POL_L POL_S _ <<<"$(vic_dims "${POLAR_WS}/panorama.img")"
    read -r POL_MEAN POL_STD _ POL_MAX <<<"$(vic_stat "${POLAR_WS}/panorama.img")"
    collect_png "${POLAR_WS}/panorama.png" "polar_mosaic"
    # A nadir-centred polar projection is square by construction.
    if [ "${POL_L}" -ge ${MIN_POLAR_DIM} ] && [ "${POL_L}" -eq "${POL_S}" ] \
       && ge "${POL_STD}" ${MIN_POLAR_STD}; then
        record PASS "polar-mosaic" \
            "${POL_L}x${POL_S} polar mosaic, mean ${POL_MEAN}, std ${POL_STD}, max ${POL_MAX} DN" \
            "images/polar_mosaic.png"
    else
        record FAIL "polar-mosaic" \
            "degenerate polar mosaic: ${POL_L}x${POL_S}, std ${POL_STD} (need square >=${MIN_POLAR_DIM}, std >=${MIN_POLAR_STD})" \
            "images/polar_mosaic.png"
    fi
else
    record FAIL "polar-mosaic" "demo-panorama-mosaic.sh --projection polar failed (rc=${POLAR_RC}), see scratch/polar/demo.log"
fi

# --- stereo -> disparity -> XYZ ---------------------------------------------

banner "Stage: stereo correlation and triangulation (marscorr/marscor3/marsxyz)"
STEREO_WS="${SCRATCH}/stereo"
mkdir -p "${STEREO_WS}"
cp "${STEREO_L}" "${STEREO_WS}/left.vic"
cp "${STEREO_R}" "${STEREO_WS}/right.vic"
( cd "${STEREO_WS}" || exit 1
  tig marscorr \( left.vic right.vic \) disparity_init.img \
      template=15 search=51 quality=0.2 seed=\("${STEREO_SEED}"\) > marscorr.log 2>&1 || exit 1
  tig marscor3 \( left.vic right.vic \) disparity.img in_disp=disparity_init.img \
      template=11 search=31 quality=0.4 -omp_on > marscor3.log 2>&1 || exit 1
  tig marsxyz \( left.vic right.vic \) pointcloud.xyz disp=disparity.img \
      error=10.0 abserr=0.15 lined=100 avgline=50 zlimit=\(-300,300\) \
      spike_range=0.04 outlier=0.5 > marsxyz.log 2>&1 )
STEREO_RC=$?

XYZ_POINTS=$(grep -oE 'Computed [0-9]+ valid XYZ points' "${STEREO_WS}/marsxyz.log" 2>/dev/null | tail -1 | awk '{print $2}')
XYZ_POINTS=${XYZ_POINTS:-0}
if [ ${STEREO_RC} -eq 0 ] && [ -s "${STEREO_WS}/pointcloud.xyz" ]; then
    read -r DISP_L DISP_S DISP_B <<<"$(vic_dims "${STEREO_WS}/disparity.img")"
    read -r _ DISP_STD _ DISP_MAX <<<"$(vic_stat "${STEREO_WS}/disparity.img")"
    read -r XYZ_L XYZ_S XYZ_B <<<"$(vic_dims "${STEREO_WS}/pointcloud.xyz")"
    make_png "${STEREO_WS}/disparity.img" "disparity" 0 "${DISP_MAX}"
    if [ "${DISP_B}" -eq 2 ] && ge "${DISP_STD}" ${MIN_DISPARITY_STD} \
       && [ "${XYZ_POINTS}" -ge ${MIN_XYZ_POINTS} ] && [ "${XYZ_B}" -eq 3 ]; then
        record PASS "stereo-xyz" \
            "${DISP_L}x${DISP_S} 2-band disparity (std ${DISP_STD}), ${XYZ_POINTS} valid XYZ points in a ${XYZ_L}x${XYZ_S}x3 cloud" \
            "images/disparity.png"
    else
        record FAIL "stereo-xyz" \
            "disparity bands ${DISP_B} std ${DISP_STD}, ${XYZ_POINTS} XYZ points (need 2 bands, std >=${MIN_DISPARITY_STD}, >=${MIN_XYZ_POINTS} points)" \
            "images/disparity.png"
    fi
else
    record FAIL "stereo-xyz" "stereo chain failed (rc=${STEREO_RC}), see scratch/stereo/marscorr.log"
fi

# --- mesh -------------------------------------------------------------------

banner "Stage: mesh (demo-mesh-generation-with-xyz.sh --xyz)"
MESH_WS="${SCRATCH}/mesh/workspace"
if [ -s "${STEREO_WS}/pointcloud.xyz" ]; then
    mkdir -p "${SCRATCH}/mesh"
    ( cd "${SCRATCH}/mesh" && "${REPO_ROOT}/demo-mesh-generation-with-xyz.sh" \
        --xyz "${STEREO_WS}/pointcloud.xyz" --texture "${STEREO_WS}/left.vic" ) \
        > "${SCRATCH}/mesh/demo.log" 2>&1
    MESH_RC=$?
else
    MESH_RC=1
fi

if [ ${MESH_RC} -eq 0 ] && [ -s "${MESH_WS}/terrain.obj" ]; then
    OBJ="${MESH_WS}/terrain.obj"
    VERTICES=$(grep -c '^v ' "${OBJ}")
    FACES=$(grep -c '^f ' "${OBJ}")
    # Every vertex must be finite and within 1e6 m of the rover frame origin.
    # marsmesh writes CRLF; strip it before parsing the coordinates.
    GEOM=$(awk '/^v /{
            gsub(/\r/, "")
            for (i = 2; i <= 4; i++) {
                v = $i
                if (v !~ /^-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?$/) { bad++; continue }
                x = v + 0
                if (x < -1e6 || x > 1e6) bad++
                if (i == 4) { if (!n || x < zmin) zmin = x; if (!n || x > zmax) zmax = x; n++ }
            }
        } END {printf "%d %.2f %.2f\n", bad+0, zmin, zmax}' "${OBJ}")
    read -r BAD_COORDS Z_MIN Z_MAX <<<"${GEOM}"
    collect_png "${MESH_WS}/texture.png" "mesh_texture"
    if [ "${VERTICES}" -ge ${MIN_VERTICES} ] && [ "${FACES}" -ge ${MIN_FACES} ] \
       && [ "${BAD_COORDS}" -eq 0 ]; then
        record PASS "mesh" \
            "${VERTICES} vertices, ${FACES} faces, all coordinates finite, elevation ${Z_MIN}..${Z_MAX} m" \
            "images/mesh_texture.png"
    else
        record FAIL "mesh" \
            "${VERTICES} vertices, ${FACES} faces, ${BAD_COORDS} non-finite/out-of-range coordinates (need >=${MIN_VERTICES}/${MIN_FACES}, 0 bad)" \
            "images/mesh_texture.png"
    fi
else
    record FAIL "mesh" "demo-mesh-generation-with-xyz.sh failed (rc=${MESH_RC}), see scratch/mesh/demo.log"
fi

# --- slope / roughness / normals --------------------------------------------

banner "Stage: surface characteristics (demo-surface-characteristics.sh)"
SURF_WS="${SCRATCH}/surface/workspace"
mkdir -p "${SCRATCH}/surface"
( cd "${SCRATCH}/surface" && "${REPO_ROOT}/demo-surface-characteristics.sh" \
    --xyz "${SURFACE_XYZ}" --texture "${STEREO_L}" --solar-angle 60 ) \
    > "${SCRATCH}/surface/demo.log" 2>&1
SURF_RC=$?

if [ ${SURF_RC} -eq 0 ] && [ -s "${SURF_WS}/slope.img" ] && [ -s "${SURF_WS}/roughness.img" ]; then
    read -r SL_L SL_S _ <<<"$(vic_dims "${SURF_WS}/slope.img")"
    read -r SL_MEAN SL_STD SL_MIN SL_MAX <<<"$(vic_stat "${SURF_WS}/slope.img")"
    read -r RG_MEAN RG_STD RG_MIN RG_MAX <<<"$(vic_stat "${SURF_WS}/roughness.img")"
    read -r XYZ_IN_L XYZ_IN_S _ <<<"$(vic_dims "${SURFACE_XYZ}")"
    collect_png "${SURF_WS}/slope.png" "slope"
    collect_png "${SURF_WS}/roughness.png" "roughness"
    collect_png "${SURF_WS}/normals.png" "normals"
    NORMALS_OK=0
    [ -s "${SURF_WS}/normals_slope.uvw" ] && [ -s "${SURF_WS}/normals_arm.uvw" ] && NORMALS_OK=1
    # Slope shares the XYZ grid, stays in degrees, roughness is a small height.
    if [ "${SL_L}" -eq "${XYZ_IN_L}" ] && [ "${SL_S}" -eq "${XYZ_IN_S}" ] \
       && ge "${SL_MIN}" 0 && le "${SL_MAX}" ${MAX_SLOPE_DEG} && ge "${SL_STD}" ${MIN_SLOPE_STD} \
       && ge "${RG_MIN}" 0 && le "${RG_MAX}" ${MAX_ROUGHNESS_M} \
       && ge "${RG_STD}" ${MIN_ROUGH_STD} && [ ${NORMALS_OK} -eq 1 ]; then
        record PASS "surface-characteristics" \
            "${SL_L}x${SL_S} products: slope mean ${SL_MEAN}deg (max ${SL_MAX}, std ${SL_STD}), roughness mean ${RG_MEAN} m (max ${RG_MAX}, std ${RG_STD}), both normals fields written" \
            "images/slope.png"
    else
        record FAIL "surface-characteristics" \
            "slope ${SL_L}x${SL_S} range ${SL_MIN}..${SL_MAX} std ${SL_STD}, roughness ${RG_MIN}..${RG_MAX} m std ${RG_STD}, normals=${NORMALS_OK} (expected ${XYZ_IN_L}x${XYZ_IN_S}, slope <=${MAX_SLOPE_DEG}deg, roughness <=${MAX_ROUGHNESS_M} m with std >=${MIN_ROUGH_STD})" \
            "images/slope.png"
    fi
else
    record FAIL "surface-characteristics" "demo-surface-characteristics.sh failed (rc=${SURF_RC}), see scratch/surface/demo.log"
fi

# --- co-registration + difference raster ------------------------------------

banner "Stage: co-registration residuals (demo-co-registration.sh)"
COREG_WS="${SCRATCH}/coreg/workspace-coreg"
mkdir -p "${SCRATCH}/coreg"
( cd "${SCRATCH}/coreg" && "${REPO_ROOT}/demo-co-registration.sh" "${PANO_FRAMES[@]}" ) \
    > "${SCRATCH}/coreg/demo.log" 2>&1
COREG_RC=$?

TIEPOINTS=0
RESID_BEFORE=""
RESID_AFTER=""
if [ ${COREG_RC} -eq 0 ] && [ -s "${COREG_WS}/pointing.nav" ]; then
    # grep -c already prints 0 when nothing matches; '|| echo 0' would double it.
    TIEPOINTS=$(grep -c '<tie ' "${COREG_WS}/tiepoints_kept.tpt" 2>/dev/null)
    TIEPOINTS=${TIEPOINTS:-0}
    RESID_BEFORE=$(grep -m1 'Commanded mean pixel error' "${COREG_WS}/marsnav.log" | awk '{print $NF}')
    RESID_AFTER=$(grep 'Final solution mean pixel error' "${COREG_WS}/marsnav.log" | tail -1 | awk '{print $NF}')

    # Same-extent mosaics with and without the solution, and their difference:
    # the visual proof that the pointing correction moved the imagery.
    ( cd "${COREG_WS}" || exit 1
      for out in raw nav; do
          nav=""
          [ "${out}" = "nav" ] && nav="navtable=pointing.nav"
          # shellcheck disable=SC2086 # nav is an optional single parameter
          tig marsmap inp=frames.lis out="mosaic_${out}.img" ${nav} -norad -nogrid \
              projection=cylindrical leftaz=45 rightaz=215 topel=15 bottomel=-40 \
              zoom=0.25 > "marsmap_${out}.log" 2>&1
      done
      tig f2 inp=\( mosaic_nav.img mosaic_raw.img \) out=coreg_diff.img \
          func=\"in1-in2\" > f2.log 2>&1 )

    read -r DIFF_MEAN DIFF_STD DIFF_MIN DIFF_MAX <<<"$(vic_stat "${COREG_WS}/coreg_diff.img")"
    make_png "${COREG_WS}/mosaic_nav.img" "coreg_mosaic" 0 4000
    # +/-1 DN so the sub-DN structure the correction introduces stays visible.
    make_png "${COREG_WS}/coreg_diff.img" "coreg_difference" -1 1

    DIFF_ABS_MEAN=$(awk -v m="${DIFF_MEAN}" 'BEGIN{print (m<0 ? -m : m)}')
    if [ -z "${RESID_BEFORE}" ] || [ -z "${RESID_AFTER}" ]; then
        # An unparsed residual is a log-format change, not an alignment regression.
        record FAIL "co-registration" \
            "cannot read the mean pixel error from scratch/coreg/workspace-coreg/marsnav.log (commanded='${RESID_BEFORE}', final='${RESID_AFTER}')" \
            "images/coreg_difference.png"
    elif [ "${TIEPOINTS}" -ge ${MIN_TIEPOINTS} ] \
       && le "${RESID_AFTER}" "${RESID_BEFORE}" && le "${RESID_AFTER}" ${MAX_COREG_RESIDUAL_PX} \
       && ge "${DIFF_STD}" 0.001 && le "${DIFF_ABS_MEAN}" ${MAX_COREG_DIFF_MEAN}; then
        record PASS "co-registration" \
            "${TIEPOINTS} tiepoints kept, mean pixel error ${RESID_BEFORE} -> ${RESID_AFTER} px, difference raster std ${DIFF_STD} DN (range ${DIFF_MIN}..${DIFF_MAX})" \
            "images/coreg_difference.png"
    else
        record FAIL "co-registration" \
            "${TIEPOINTS} tiepoints, residual ${RESID_BEFORE} -> ${RESID_AFTER} px, diff std ${DIFF_STD} mean ${DIFF_MEAN} (need >=${MIN_TIEPOINTS} tiepoints, residual improved and <=${MAX_COREG_RESIDUAL_PX} px, non-zero diff)" \
            "images/coreg_difference.png"
    fi
else
    record FAIL "co-registration" "demo-co-registration.sh failed (rc=${COREG_RC}), see scratch/coreg/demo.log"
fi

# --- two-epoch change product (only if the demo ships) ----------------------

banner "Stage: two-epoch change monitoring"
CHANGE_DEMO="${REPO_ROOT}/demo-change-monitoring.sh"
# Only drive the demo through the interface this stage was written against; a
# different one is a suite gap to close, not a broken image.
CHANGE_IFACE=0
[ -x "${CHANGE_DEMO}" ] && "${CHANGE_DEMO}" --help 2>&1 | grep -q -- '--epoch1' && CHANGE_IFACE=1
if [ ! -x "${CHANGE_DEMO}" ]; then
    record UNVERIFIED "change-monitoring" \
        "demo-change-monitoring.sh is not in this tree; the stage runs automatically once it is"
elif [ ${CHANGE_IFACE} -eq 0 ]; then
    record UNVERIFIED "change-monitoring" \
        "demo-change-monitoring.sh does not advertise --epoch1/--epoch2; update this stage to its current interface"
else
    CHANGE_WS="${SCRATCH}/change/workspace-change"
    mkdir -p "${SCRATCH}/change"
    ( cd "${SCRATCH}/change" && "${REPO_ROOT}/demo-change-monitoring.sh" \
        --epoch1 "${PANO_FRAMES[0]}" --epoch2 "${PANO_FRAMES[1]}" \
        --overlap "${CHANGE_OVERLAP}" --bounds "${CHANGE_BOUNDS}" ) \
        > "${SCRATCH}/change/demo.log" 2>&1
    CHANGE_RC=$?
    # diff_lin.img is the mean/stdev-matched difference raster the demo reports on.
    CHANGE_DIFF=$(find "${CHANGE_WS}" -name 'diff_lin.img' 2>/dev/null | head -1)
    [ -n "${CHANGE_DIFF}" ] || CHANGE_DIFF=$(find "${CHANGE_WS}" -name 'diff*.img' 2>/dev/null | head -1)
    if [ ${CHANGE_RC} -eq 0 ] && [ -n "${CHANGE_DIFF}" ]; then
        read -r CH_MEAN CH_STD CH_MIN CH_MAX <<<"$(vic_stat "${CHANGE_DIFF}")"
        make_png "${CHANGE_DIFF}" "change_difference" "${CH_MIN}" "${CH_MAX}"
        if ge "${CH_STD}" 0.001; then
            record PASS "change-monitoring" \
                "difference raster mean ${CH_MEAN}, std ${CH_STD}, range ${CH_MIN}..${CH_MAX} DN" \
                "images/change_difference.png"
        else
            record FAIL "change-monitoring" "difference raster is uniform (std ${CH_STD})" \
                "images/change_difference.png"
        fi
    elif [ ${CHANGE_RC} -eq 0 ]; then
        record UNVERIFIED "change-monitoring" \
            "demo-change-monitoring.sh ran but wrote no diff*.img in ${CHANGE_WS}; update this stage to its current product names"
    else
        record FAIL "change-monitoring" "demo-change-monitoring.sh failed (rc=${CHANGE_RC}), see scratch/change/demo.log"
    fi
fi

banner "Stage: demo built-in stereo path"
record UNVERIFIED "demo-stereo-path" \
    "demo-mesh-generation-with-xyz.sh --stereo-left/--stereo-right uses marscorr's default seed, which reports 'No valid seed points found' on these Navcam frames; this suite seeds the frame centre itself (seed=${STEREO_SEED})"

# --- report -----------------------------------------------------------------

SUITE_END=$(date +%s)
ELAPSED=$(( SUITE_END - SUITE_START ))
RUNTIME_STR=$(printf '%dm%02ds' $(( ELAPSED / 60 )) $(( ELAPSED % 60 )))

{
    echo "# TIG release visual regression report"
    echo ""
    echo "| | |"
    echo "|---|---|"
    echo "| image | \`${IMAGE_TAG}\` |"
    echo "| data | VICAR 5.0 VISOR sample data (MSL Navcam), \`${SAMPLE_DIR}\` |"
    echo "| calibration | \`${CALIB_DIR}\` |"
    echo "| host | $(uname -srm), $(nproc) CPUs |"
    echo "| finished | $(date -u '+%Y-%m-%d %H:%M:%S UTC') |"
    echo "| runtime | ${RUNTIME_STR} |"
    echo "| result | ${STAGES_PASSED} passed, ${STAGES_FAILED} failed, ${STAGES_UNVERIFIED} unverified |"
    echo ""
    echo "## Stages"
    echo ""
    echo "| stage | result | evidence |"
    echo "|---|---|---|"
    for row in "${ROWS[@]}"; do
        IFS='|' read -r name status detail _ <<<"${row}"
        case "${status}" in
            PASS) mark="PASS" ;;
            FAIL) mark="**FAIL**" ;;
            *)    mark="UNVERIFIED" ;;
        esac
        echo "| ${name} | ${mark} | ${detail} |"
    done
    echo ""
    echo "## Images"
    echo ""
    echo "Every image below was produced by this run; the assertions above are"
    echo "on the products these images render."
    for row in "${ROWS[@]}"; do
        IFS='|' read -r name status detail png <<<"${row}"
        if [ -z "${png}" ] || [ ! -s "${OUT_DIR}/${png}" ]; then continue; fi
        echo ""
        echo "### ${name} (${status})"
        echo ""
        echo "${detail}"
        echo ""
        echo "![${name}](${png})"
    done
    echo ""
    echo "## Unverified"
    echo ""
    UNVER=0
    for row in "${ROWS[@]}"; do
        IFS='|' read -r name status detail _ <<<"${row}"
        [ "${status}" = "UNVERIFIED" ] || continue
        echo "- **${name}**: ${detail}"
        UNVER=1
    done
    [ ${UNVER} -eq 0 ] && echo "None: every stage ran."
} > "${REPORT}"

banner "Summary"
echo "runtime:     ${RUNTIME_STR}"
echo "report:      ${REPORT}"
echo "images:      $(find "${IMAGE_DIR}" -name '*.png' | wc -l) PNGs in ${IMAGE_DIR}"
echo -e "${GREEN}passed:      ${STAGES_PASSED}${NC}"
echo -e "${YELLOW}unverified:  ${STAGES_UNVERIFIED}${NC}"
echo -e "${RED}failed:      ${STAGES_FAILED}${NC}"

if [ ${KEEP_SCRATCH} -eq 0 ] && [ ${STAGES_FAILED} -eq 0 ]; then
    rm -rf "${SCRATCH}"
fi

if [ ${STAGES_FAILED} -gt 0 ]; then
    echo -e "${RED}Release regression FAILED${NC}"
    exit 1
fi
echo -e "${GREEN}Release regression passed${NC}"
exit 0
