#!/bin/sh
#
# install-visor-calibration.sh - Download and install VISOR mission calibration
#
# Runs inside a docker build (visor/Dockerfile and fullfeatured/Dockerfile both
# use it), so it is /bin/sh only and takes its inputs from the environment:
#
#   VISOR_CALIB               destination root; one directory per mission
#   VISOR_CHECKSUMS           file of pinned "<sha256>  <asset>" lines
#   VICAR_VERSION             VICAR release the calibration assets belong to
#   VISOR_CALIBRATION_DATE    date stamp in the asset names
#   VISOR_SPLIT_SUFFIXES      suffixes probed when an asset is split
#
# Usage: install-visor-calibration.sh <mission>...
#
# Download, verify, extract and delete the archives in one pass: compressed
# calibration is the same order of magnitude as extracted calibration, so
# keeping the downloads would nearly double the image. Every part is checked
# against its pinned digest before anything is extracted, and an asset with no
# pinned digest fails the build.

set -eu

: "${VISOR_CALIB:?VISOR_CALIB is not set}"
: "${VISOR_CHECKSUMS:=/usr/local/share/visor-calibration.sha256}"
: "${VICAR_VERSION:=5.0}"
: "${VISOR_CALIBRATION_DATE:=20230608}"
: "${VISOR_SPLIT_SUFFIXES:=aa ab ac ad ae af ag ah}"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <mission>..." >&2
    exit 1
fi

base_url="https://github.com/NASA-AMMOS/VICAR/releases/download/${VICAR_VERSION}"
staging=/tmp/visor-staging
downloads=/tmp/visor-downloads

mkdir -p "${VISOR_CALIB}"

for mission in "$@"; do
    asset="visor_calibration_${VISOR_CALIBRATION_DATE}_${mission}.tar.gz"
    url="${base_url}/${asset}"

    # GitHub caps a release asset at 2GB, so the larger missions are split with
    # split(1) and have to be concatenated before they can be extracted.
    if curl --proto '=https' --proto-redir '=https' -fsIL -o /dev/null "${url}"; then
        names="${asset}"
    else
        names=""
        for suffix in ${VISOR_SPLIT_SUFFIXES}; do
            curl --proto '=https' --proto-redir '=https' -fsIL -o /dev/null "${url}${suffix}" || break
            names="${names} ${asset}${suffix}"
        done
    fi

    if [ -z "${names}" ]; then
        echo "No release asset ${asset}, whole or split, in VICAR ${VICAR_VERSION}" >&2
        exit 1
    fi

    rm -rf "${staging}" "${downloads}"
    mkdir -p "${staging}" "${downloads}"
    parts=""
    for name in ${names}; do
        expected=$(awk -v n="${name}" '$2 == n { print $1 }' "${VISOR_CHECKSUMS}")
        if [ -z "${expected}" ]; then
            echo "No pinned SHA-256 for ${name}; regenerate calibration.sha256" >&2
            exit 1
        fi
        echo "Fetching ${base_url}/${name}"
        curl --proto '=https' --proto-redir '=https' -fsSL -o "${downloads}/${name}" "${base_url}/${name}"
        echo "${expected}  ${downloads}/${name}" | sha256sum -c - > /dev/null \
            || { echo "SHA-256 mismatch for ${name}" >&2; exit 1; }
        parts="${parts} ${downloads}/${name}"
    done

    # shellcheck disable=SC2086 # parts is a deliberately word-split path list
    cat ${parts} | tar -xz -C "${staging}"
    rm -rf "${downloads}"
    if [ -d "${staging}/calibration/${mission}" ]; then
        mv "${staging}/calibration/${mission}" "${VISOR_CALIB}/${mission}"
    else
        mkdir -p "${VISOR_CALIB}/${mission}"
        mv "${staging}"/* "${VISOR_CALIB}/${mission}/"
    fi
    rm -rf "${staging}"
    echo "${mission}: $(du -sh "${VISOR_CALIB}/${mission}" | cut -f1) extracted"
done

chmod -R a+rX "${VISOR_CALIB}"

# Fail the build rather than publish an image whose calibration the tools would
# not find.
for mission in "$@"; do
    test -d "${VISOR_CALIB}/${mission}/camera_models" \
        || { echo "No camera models for ${mission}" >&2; exit 1; }
    case ":${MARS_CONFIG_PATH:-}:" in
        *":${VISOR_CALIB}/${mission}:"*) ;;
        *) echo "${mission} is not on MARS_CONFIG_PATH" >&2; exit 1;;
    esac
done

echo "VISOR calibration bundled: $* ($(du -sh "${VISOR_CALIB}" | cut -f1))"
