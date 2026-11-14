# Terrain Intelligence Generator - Builder image
#
# The runtime image cannot compile: it has no compilers, and the optimization
# that takes it from ~8GB to ~3GB deletes the headers, the imakefiles, the
# program sources and the external link archives a build needs. This image is
# the same VICAR release with none of that removed, plus the toolchain, and is
# what 'tig --build' compiles in.
#
# Build it locally with ../build-builder-image.sh; it is deliberately not
# published, so the VICAR release tarballs are only ever fetched by the user.
#
# Outside docker/, like visor/, because the runtime image's workflow rebuilds on
# any change under that directory.
FROM oraclelinux:8

ARG VICAR_VERSION=5.0
ARG BINARIES_FILE=vicar_open_bin_x86-64-linx_5.0.tar.gz
ARG EXTERNAL_FILE=vicar_open_ext_x86-64-linx_5.0.tar.gz

LABEL org.opencontainers.image.title="Terrain Intelligence Generator (builder)"
LABEL org.opencontainers.image.description="VICAR build environment for compiling program units from source"
LABEL org.opencontainers.image.source="https://github.com/NASA-AMMOS/VICAR"
# 'tig --build' compares this with the runtime image's label: a unit links
# against the runtime image's own libraries, so the two must be one release.
LABEL org.nasa.tig.vicar-version="${VICAR_VERSION}"

ENV V2TOP=/usr/local/vicar/dev
ENV WORKSPACE=/usr/local/vicar
ENV VICSYS=DEVELOPMENT
ENV VICCPU=x86-64-linx
ENV SHELL=/bin/bash

# vimake is a thin wrapper over imake, which lives in EPEL; the X11, Motif,
# ncurses and TBB headers are all reached indirectly - $V2TOP/crumbs includes
# X11 headers even for headless programs, and libembree3 pulls in TBB - so a
# MARS program will not link without them.
RUN dnf install -y oracle-epel-release-el8 || dnf install -y epel-release; \
    dnf config-manager --set-enabled ol8_codeready_builder || true; \
    dnf install -y \
        gcc gcc-c++ gcc-gfortran make imake perl tcsh \
        curl tar gzip findutils which diffutils \
        libX11-devel libXt-devel libXext-devel libXmu-devel libXp-devel \
        motif-devel ncurses-devel tbb-devel \
        libjpeg-turbo-devel libpng-devel libtiff-devel zlib-devel \
        tcl-devel tk-devel \
    && dnf clean all && rm -rf /var/cache/dnf /var/cache/yum

RUN rm -f /bin/csh && ln -s /bin/tcsh /bin/csh

# The binaries tarball ships the sources too, so $V2TOP/mars/src/prog and
# $V2TOP/p2/prog are available as a reference tree to copy a unit from.
RUN echo "Downloading VICAR binaries and sources..." && \
    curl --proto "=https" --tlsv1.2 -fL "https://github.com/NASA-AMMOS/VICAR/releases/download/${VICAR_VERSION}/${BINARIES_FILE}" -o /tmp/vicar_bin.tar.gz && \
    mkdir -p ${V2TOP} && cd /tmp && tar -xzf vicar_bin.tar.gz && \
    EXTRACTED_DIR=$(ls -d vicar_open_bin_* 2>/dev/null | head -1) && \
    if [ -d "$EXTRACTED_DIR/vicar_open_${VICAR_VERSION}" ]; then \
        cp -r "$EXTRACTED_DIR/vicar_open_${VICAR_VERSION}"/* ${V2TOP}/; \
    else \
        cp -r "$EXTRACTED_DIR"/* ${V2TOP}/; \
    fi && \
    rm -rf /tmp/vicar_bin.tar.gz "/tmp/$EXTRACTED_DIR" && \
    echo "✓ VICAR $(du -sh ${V2TOP} | cut -f1) unpacked"

RUN echo "Downloading VICAR external libraries..." && \
    curl --proto "=https" --tlsv1.2 -fL "https://github.com/NASA-AMMOS/VICAR/releases/download/${VICAR_VERSION}/${EXTERNAL_FILE}" -o /tmp/vicar_ext.tar.gz && \
    mkdir -p ${WORKSPACE}/external && cd /tmp && tar -xzf vicar_ext.tar.gz && \
    EXTRACTED_DIR=$(ls -d vicar_open_ext_* 2>/dev/null | head -1) && \
    CONTENT_COUNT=$(find "$EXTRACTED_DIR" -maxdepth 1 -mindepth 1 | wc -l) && \
    if [ "$CONTENT_COUNT" -eq 1 ]; then \
        SUBDIR=$(find "$EXTRACTED_DIR" -maxdepth 1 -mindepth 1 -type d | head -1); \
        if [ -n "$SUBDIR" ]; then cp -r "$SUBDIR"/* ${WORKSPACE}/external/; fi; \
    else \
        cp -r "$EXTRACTED_DIR"/* ${WORKSPACE}/external/; \
    fi && \
    rm -rf /tmp/vicar_ext.tar.gz "/tmp/$EXTRACTED_DIR" && \
    echo "✓ Externals $(du -sh ${WORKSPACE}/external | cut -f1) unpacked"

COPY --chown=root:root vicar-build /usr/local/bin/vicar-build
RUN chmod +x /usr/local/bin/vicar-build

# Builds run as the invoking user, who has no home directory here; vimake and
# make need none, but a writable temporary directory is used by both.
ENV TMPDIR=/tmp

WORKDIR /build

RUN echo "===== Builder verification =====" && \
    test -f ${V2TOP}/vicset1.csh && test -f ${V2TOP}/vicset2.csh && \
    test -f ${V2TOP}/util/imake_unix.tmpl && \
    test -n "$(ls ${V2TOP}/rtl/inc/*.h)" && \
    test -n "$(ls ${V2TOP}/olb/${VICCPU}/*.a)" && \
    echo "✓ headers, archives and imake templates present"

CMD ["/bin/bash"]
