# Terrain Intelligence Generator - Open Source Build (Optimized)
# Uses pre-built VICAR binaries from GitHub releases
# Based on Oracle Linux 8 (RHEL-compatible)
# 
# This is a multi-stage build that reduces image size from ~8GB to ~2GB
# by downloading and extracting archives in a builder stage, then copying
# only the final files to the runtime stage.

# ============================================================================
# Stage 1: Builder - Download and extract VICAR archives
# ============================================================================
FROM oraclelinux:8 AS builder

ARG VICAR_VERSION=5.0
ARG BINARIES_FILE=vicar_open_bin_x86-64-linx_5.0.tar.gz
ARG EXTERNAL_FILE=vicar_open_ext_x86-64-linx_5.0.tar.gz

WORKDIR /build

# Install minimal tools for downloading
RUN dnf install -y curl tar gzip && \
    dnf clean all

# Download and extract VICAR binaries
RUN echo "Downloading VICAR binaries..." && \
    curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/${VICAR_VERSION}/${BINARIES_FILE}" -o vicar_bin.tar.gz && \
    echo "Extracting VICAR binaries..." && \
    mkdir -p /vicar/dev && \
    tar -xzf vicar_bin.tar.gz && \
    EXTRACTED_DIR=$(ls -d vicar_open_bin_* 2>/dev/null | head -1) && \
    if [ -d "$EXTRACTED_DIR/vicar_open_5.0" ]; then \
        cp -r "$EXTRACTED_DIR/vicar_open_5.0"/* /vicar/dev/; \
    else \
        cp -r "$EXTRACTED_DIR"/* /vicar/dev/; \
    fi && \
    echo "✓ VICAR binaries extracted" && \
    echo "Removing unnecessary files (source, docs, tests)..." && \
    cd /vicar/dev && \
    rm -rf p2/prog p3/prog mars/src && \
    rm -rf html docsource && \
    rm -rf p2/sub/*/test p3/sub/*/test && \
    find . -name "*.c" -delete && \
    find . -name "*.cc" -delete && \
    find . -name "*.cpp" -delete && \
    find . -name "*.h" -delete && \
    find . -name "*.imake" -delete && \
    find . -name "*.log" -delete && \
    find . -name "test" -type d -exec rm -rf {} + 2>/dev/null || true && \
    echo "✓ Cleaned $(du -sh /vicar/dev | cut -f1) remaining"

# Download and extract VICAR external libraries
RUN echo "Downloading VICAR external libraries..." && \
    curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/${VICAR_VERSION}/${EXTERNAL_FILE}" -o vicar_ext.tar.gz && \
    echo "Extracting VICAR external libraries..." && \
    mkdir -p /vicar/external && \
    tar -xzf vicar_ext.tar.gz && \
    EXTRACTED_DIR=$(ls -d vicar_open_ext_* 2>/dev/null | head -1) && \
    CONTENT_COUNT=$(find "$EXTRACTED_DIR" -maxdepth 1 -mindepth 1 | wc -l) && \
    if [ "$CONTENT_COUNT" -eq 1 ]; then \
        SUBDIR=$(find "$EXTRACTED_DIR" -maxdepth 1 -mindepth 1 -type d | head -1); \
        if [ -n "$SUBDIR" ]; then \
            cp -r "$SUBDIR"/* /vicar/external/; \
        fi; \
    else \
        cp -r "$EXTRACTED_DIR"/* /vicar/external/; \
    fi && \
    echo "✓ External libraries extracted" && \
    echo "Removing unnecessary files from external libraries..." && \
    cd /vicar/external && \
    find . -name "*.h" -delete && \
    find . -name "*.hpp" -delete && \
    find . -name "*.hxx" -delete && \
    find . -name "*.c" -delete && \
    find . -name "*.cc" -delete && \
    find . -name "*.cpp" -delete && \
    find . -name "*.cxx" -delete && \
    find . -name "*.a" -delete && \
    find . -name "*.cmake" -delete && \
    find . -name "CMakeLists.txt" -delete && \
    rm -rf */include */src */test */tests */examples */doc */docs && \
    echo "✓ Cleaned $(du -sh /vicar/external | cut -f1) remaining"

# ============================================================================
# Stage 2: Runtime - Build final image with only necessary files
# ============================================================================
FROM oraclelinux:8

LABEL org.opencontainers.image.title="Terrain Intelligence Generator"
LABEL org.opencontainers.image.description="Open source distribution of VICAR-based terrain intelligence generation tools (optimized)"
LABEL org.opencontainers.image.version="5.0-opensource-optimized"
LABEL org.opencontainers.image.source="https://github.com/NASA-AMMOS/VICAR"

# Set VICAR environment
ENV V2TOP=/usr/local/vicar/dev
ENV WORKSPACE=/usr/local/vicar
ENV VICSYS=DEVELOPMENT
ENV SHELL=/bin/bash
ENV PATH="${V2TOP}/p2/lib/x86-64-linx:${V2TOP}/tae53/bin/x86_64_linx:${PATH}"
ENV LD_LIBRARY_PATH="${V2TOP}/olb/x86-64-linx:${V2TOP}/p2/lib/x86-64-linx:${V2TOP}/mars/lib/x86-64-linx"

# Enable PowerTools (CodeReady Builder) for additional packages
RUN dnf install -y dnf-plugins-core && \
    dnf config-manager --enable ol8_codeready_builder && \
    dnf clean all

# Install runtime dependencies
RUN dnf -y --nogpgcheck --setopt=install_weak_deps=False --setopt=tsflags=nodocs install \
    # Essential runtime libraries
    libgfortran \
    libgomp \
    libquadmath \
    # Shells
    tcsh \
    bash \
    # X11 runtime libraries
    libX11 \
    libXext \
    libXmu \
    libXi \
    libXt \
    xauth \
    # Motif runtime
    motif \
    # Java runtime (Java 11 headless for vicario.jar)
    java-11-openjdk-headless \
    # Image processing runtime libraries
    libtiff \
    libpng \
    libjpeg-turbo \
    # Network and system libraries
    libcurl \
    libtirpc \
    sqlite-libs \
    tbb \
    openssl-libs \
    tcl \
    tk \
    # Minimal utilities
    less \
    which \
    findutils \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/cache/yum

# Create library compatibility symlinks
RUN ln -sf /lib64/libtcl8.6.so /lib64/libtcl.so && \
    ln -sf /lib64/libtk8.6.so /lib64/libtk.so && \
    ln -sf /lib64/libcrypto.so /lib64/libcrypto.so 2>/dev/null || true

# Create csh symlink
RUN rm -f /bin/csh && ln -s /bin/tcsh /bin/csh

# Create VICAR directory structure
RUN mkdir -p ${WORKSPACE}/dev ${WORKSPACE}/build/{java,html/{bin,xsl}}

# Copy VICAR files from builder stage (this is the key optimization!)
COPY --from=builder /vicar/dev ${WORKSPACE}/dev
COPY --from=builder /vicar/external ${WORKSPACE}/external

# Copy Java vicario JAR and create wrapper script
COPY --chown=root:root vicario.jar /usr/local/bin/vicario.jar

# Create vicario wrapper script that uses Java in headless mode
RUN echo '#!/bin/bash' > /usr/local/bin/vicario && \
    echo '# vicario wrapper - calls Java vicario in headless mode (no X11 required)' >> /usr/local/bin/vicario && \
    echo 'VICARIO_JAR="/usr/local/bin/vicario.jar"' >> /usr/local/bin/vicario && \
    echo '' >> /usr/local/bin/vicario && \
    echo '# Temporary files for filtering output' >> /usr/local/bin/vicario && \
    echo 'TMPOUT=$(mktemp)' >> /usr/local/bin/vicario && \
    echo 'TMPERR=$(mktemp)' >> /usr/local/bin/vicario && \
    echo 'trap "rm -f $TMPOUT $TMPERR" EXIT' >> /usr/local/bin/vicario && \
    echo '' >> /usr/local/bin/vicario && \
    echo '# Parse simple input/output format' >> /usr/local/bin/vicario && \
    echo 'if [ $# -eq 2 ]; then' >> /usr/local/bin/vicario && \
    echo '    INP="$1"' >> /usr/local/bin/vicario && \
    echo '    OUT="$2"' >> /usr/local/bin/vicario && \
    echo '    # Auto-detect format from extension' >> /usr/local/bin/vicario && \
    echo '    EXT="${OUT##*.}"' >> /usr/local/bin/vicario && \
    echo '    FORMAT=$(echo "$EXT" | tr '"'"'[:upper:]'"'"' '"'"'[:lower:]'"'"')' >> /usr/local/bin/vicario && \
    echo '    # Run Java vicario in headless mode' >> /usr/local/bin/vicario && \
    echo '    java -Djava.awt.headless=true -jar "$VICARIO_JAR" inp="$INP" out="$OUT" format="$FORMAT" oform=byte rescale=true > $TMPOUT 2> $TMPERR' >> /usr/local/bin/vicario && \
    echo 'else' >> /usr/local/bin/vicario && \
    echo '    # Pass through all arguments as-is' >> /usr/local/bin/vicario && \
    echo '    java -Djava.awt.headless=true -jar "$VICARIO_JAR" "$@" > $TMPOUT 2> $TMPERR' >> /usr/local/bin/vicario && \
    echo 'fi' >> /usr/local/bin/vicario && \
    echo '' >> /usr/local/bin/vicario && \
    echo 'EXIT_CODE=$?' >> /usr/local/bin/vicario && \
    echo '' >> /usr/local/bin/vicario && \
    echo '# Filter stderr - suppress mediaLib/mlib warnings and stack traces' >> /usr/local/bin/vicario && \
    echo 'sed "/mediaLib\|mlib\|MediaLib/d; /^\tat /d; /^Caused by:/d; /^Occurs in:/d; /^\.\.\. [0-9]* more$/d" $TMPERR >&2' >> /usr/local/bin/vicario && \
    echo '' >> /usr/local/bin/vicario && \
    echo '# Output stdout' >> /usr/local/bin/vicario && \
    echo 'cat $TMPOUT' >> /usr/local/bin/vicario && \
    echo '' >> /usr/local/bin/vicario && \
    echo 'exit $EXIT_CODE' >> /usr/local/bin/vicario && \
    chmod +x /usr/local/bin/vicario

WORKDIR /workspace

# Create symbolic links for common VICAR commands in /usr/local/bin
RUN ARCH_DIR="x86-64-linx" && \
    TAE_ARCH_DIR="x86_64_linx" && \
    echo "Creating wrapper scripts for VICAR commands..." && \
    # Build comprehensive library path
    VICAR_LIB_PATH="${V2TOP}/olb/$ARCH_DIR:${V2TOP}/mars/lib/$ARCH_DIR" && \
    for extlib in ${WORKSPACE}/external/*/v*/$ARCH_DIR/lib ${WORKSPACE}/external/*/v*/$ARCH_DIR/lib64 ${WORKSPACE}/external/*/v*/$ARCH_DIR; do \
        if [ -d "$extlib" ]; then \
            VICAR_LIB_PATH="$VICAR_LIB_PATH:$extlib"; \
        fi; \
    done && \
    # Create wrappers for VICAR p2 programs
    if [ -d "${V2TOP}/p2/lib/$ARCH_DIR" ]; then \
        WRAPPER_COUNT=0; \
        for cmd in ${V2TOP}/p2/lib/$ARCH_DIR/*; do \
            if [ -f "$cmd" ] && [ -x "$cmd" ]; then \
                cmdname=$(basename "$cmd"); \
                if [[ ! "$cmdname" =~ \. ]]; then \
                    echo "#!/bin/bash" > /usr/local/bin/$cmdname; \
                    echo "export V2TOP=${V2TOP}" >> /usr/local/bin/$cmdname; \
                    echo "export WORKSPACE=${WORKSPACE}" >> /usr/local/bin/$cmdname; \
                    echo "export VICSYS=DEVELOPMENT" >> /usr/local/bin/$cmdname; \
                    echo "export LD_LIBRARY_PATH=$VICAR_LIB_PATH:\$LD_LIBRARY_PATH" >> /usr/local/bin/$cmdname; \
                    echo "export PATH=${V2TOP}/p2/lib/$ARCH_DIR:${V2TOP}/tae53/bin/$TAE_ARCH_DIR:\$PATH" >> /usr/local/bin/$cmdname; \
                    echo "$cmd \"\$@\"" >> /usr/local/bin/$cmdname; \
                    echo "exit_code=\$?" >> /usr/local/bin/$cmdname; \
                    echo "# VICAR commands often return non-zero on success, treat 0-2 as success" >> /usr/local/bin/$cmdname; \
                    echo "if [ \$exit_code -le 2 ]; then exit 0; else exit \$exit_code; fi" >> /usr/local/bin/$cmdname; \
                    chmod +x /usr/local/bin/$cmdname; \
                    WRAPPER_COUNT=$((WRAPPER_COUNT + 1)); \
                fi; \
            fi; \
        done; \
        echo "✓ Created $WRAPPER_COUNT wrappers for VICAR p2 commands"; \
    fi && \
    # Create wrappers for TAE binaries
    if [ -d "${V2TOP}/tae53/bin/$TAE_ARCH_DIR" ]; then \
        TAE_COUNT=0; \
        for cmd in ${V2TOP}/tae53/bin/$TAE_ARCH_DIR/*; do \
            if [ -f "$cmd" ] && [ -x "$cmd" ]; then \
                cmdname=$(basename "$cmd"); \
                if [ ! -f "/usr/local/bin/$cmdname" ]; then \
                    echo "#!/bin/bash" > /usr/local/bin/$cmdname; \
                    echo "export V2TOP=${V2TOP}" >> /usr/local/bin/$cmdname; \
                    echo "export WORKSPACE=${WORKSPACE}" >> /usr/local/bin/$cmdname; \
                    echo "export VICSYS=DEVELOPMENT" >> /usr/local/bin/$cmdname; \
                    echo "export LD_LIBRARY_PATH=$VICAR_LIB_PATH:\$LD_LIBRARY_PATH" >> /usr/local/bin/$cmdname; \
                    echo "export PATH=${V2TOP}/tae53/bin/$TAE_ARCH_DIR:${V2TOP}/tae53/bin/all:\$PATH" >> /usr/local/bin/$cmdname; \
                    echo "$cmd \"\$@\"" >> /usr/local/bin/$cmdname; \
                    echo "exit_code=\$?" >> /usr/local/bin/$cmdname; \
                    echo "# VICAR commands often return non-zero on success, treat 0-2 as success" >> /usr/local/bin/$cmdname; \
                    echo "if [ \$exit_code -le 2 ]; then exit 0; else exit \$exit_code; fi" >> /usr/local/bin/$cmdname; \
                    chmod +x /usr/local/bin/$cmdname; \
                    TAE_COUNT=$((TAE_COUNT + 1)); \
                fi; \
            fi; \
        done; \
        echo "✓ Created $TAE_COUNT wrappers for TAE commands"; \
    fi && \
    # Create wrappers for MARS binaries
    if [ -d "${V2TOP}/mars/lib/$ARCH_DIR" ]; then \
        MARS_COUNT=0; \
        for cmd in ${V2TOP}/mars/lib/$ARCH_DIR/*; do \
            if [ -f "$cmd" ] && [ -x "$cmd" ]; then \
                cmdname=$(basename "$cmd"); \
                if [[ ! "$cmdname" =~ \. ]] && [ ! -f "/usr/local/bin/$cmdname" ]; then \
                    echo "#!/bin/bash" > /usr/local/bin/$cmdname; \
                    echo "export V2TOP=${V2TOP}" >> /usr/local/bin/$cmdname; \
                    echo "export WORKSPACE=${WORKSPACE}" >> /usr/local/bin/$cmdname; \
                    echo "export VICSYS=DEVELOPMENT" >> /usr/local/bin/$cmdname; \
                    echo "export LD_LIBRARY_PATH=$VICAR_LIB_PATH:\$LD_LIBRARY_PATH" >> /usr/local/bin/$cmdname; \
                    echo "export PATH=${V2TOP}/mars/lib/$ARCH_DIR:${V2TOP}/p2/lib/$ARCH_DIR:\$PATH" >> /usr/local/bin/$cmdname; \
                    echo "$cmd \"\$@\"" >> /usr/local/bin/$cmdname; \
                    echo "exit_code=\$?" >> /usr/local/bin/$cmdname; \
                    echo "# VICAR commands often return non-zero on success, treat 0-2 as success" >> /usr/local/bin/$cmdname; \
                    echo "if [ \$exit_code -le 2 ]; then exit 0; else exit \$exit_code; fi" >> /usr/local/bin/$cmdname; \
                    chmod +x /usr/local/bin/$cmdname; \
                    MARS_COUNT=$((MARS_COUNT + 1)); \
                fi; \
            fi; \
        done; \
        echo "✓ Created $MARS_COUNT wrappers for MARS commands"; \
    fi

# Set up VICAR environment for profile scripts
RUN ARCH_DIR="x86-64-linx" && \
    VICAR_LIB_PATH="${V2TOP}/olb/$ARCH_DIR:${V2TOP}/mars/lib/$ARCH_DIR" && \
    for extlib in ${WORKSPACE}/external/*/v*/$ARCH_DIR/lib ${WORKSPACE}/external/*/v*/$ARCH_DIR/lib64 ${WORKSPACE}/external/*/v*/$ARCH_DIR; do \
        if [ -d "$extlib" ]; then \
            VICAR_LIB_PATH="$VICAR_LIB_PATH:$extlib"; \
        fi; \
    done && \
    echo "export V2TOP=${V2TOP}" > /etc/profile.d/vicar.sh && \
    echo "export WORKSPACE=${WORKSPACE}" >> /etc/profile.d/vicar.sh && \
    echo "export VICSYS=DEVELOPMENT" >> /etc/profile.d/vicar.sh && \
    echo "export LD_LIBRARY_PATH=$VICAR_LIB_PATH:\$LD_LIBRARY_PATH" >> /etc/profile.d/vicar.sh && \
    echo "export PATH=${V2TOP}/tae53/bin:${V2TOP}/bin:\$PATH" >> /etc/profile.d/vicar.sh && \
    chmod +x /etc/profile.d/vicar.sh

# Verify VICAR installation
RUN echo "===== VICAR Installation Verification =====" && \
    echo "V2TOP: ${V2TOP}" && \
    echo "" && \
    if [ -d "${V2TOP}" ]; then \
        echo "✓ Found VICAR at ${V2TOP}"; \
        if [ -d "${V2TOP}/tae53/bin" ]; then \
            TAE_COUNT=$(find ${V2TOP}/tae53/bin -type f -executable 2>/dev/null | wc -l); \
            echo "✓ TAE binaries: $TAE_COUNT programs"; \
        fi; \
        if [ -d "${V2TOP}/p2/lib/x86-64-linx" ]; then \
            P2_COUNT=$(find ${V2TOP}/p2/lib/x86-64-linx -type f -executable 2>/dev/null | wc -l); \
            echo "✓ P2 programs: $P2_COUNT"; \
        fi; \
        if [ -d "${V2TOP}/mars/lib/x86-64-linx" ]; then \
            MARS_COUNT=$(find ${V2TOP}/mars/lib/x86-64-linx -type f -executable 2>/dev/null | wc -l); \
            echo "✓ MARS programs: $MARS_COUNT"; \
        fi; \
    else \
        echo "✗ VICAR directory not found at ${V2TOP}"; \
        exit 1; \
    fi && \
    echo "" && \
    echo "Checking vicario installation:" && \
    test -x /usr/local/bin/vicario && echo "✓ vicario installed" || echo "✗ vicario not found"

# Create entrypoint script
RUN echo '#!/bin/bash' > /usr/local/bin/docker-entrypoint.sh && \
    echo 'source /etc/profile.d/vicar.sh 2>/dev/null || true' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'exec "$@"' >> /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Display installation summary
RUN echo "===== Terrain Intelligence Generator Installation Complete =====" && \
    echo "V2TOP: ${V2TOP}" && \
    echo "Source: Pre-built binaries from https://github.com/NASA-AMMOS/VICAR/releases" && \
    echo "Build: Optimized multi-stage build (reduced from ~8GB to ~2GB)" && \
    echo "" && \
    echo "Available wrappers in /usr/local/bin: $(ls -1 /usr/local/bin | wc -l)" && \
    echo "" && \
    echo "Common VICAR commands to try:" && \
    echo "  tae         - TAE command interpreter" && \
    echo "  label       - Display image labels" && \
    echo "  list        - List file contents" && \
    echo "  gen         - Generate test images" && \
    echo "  marsmap     - MARS terrain mapping" && \
    echo "  marsmos     - MARS mosaic generation" && \
    echo "  vicario     - Convert VICAR images to PNG/JPEG/TIFF" && \
    echo "" && \
    echo "Note: VISOR calibration and sample data not bundled." && \
    echo "Mount externally or download from VICAR releases."

# Keep container running
CMD ["tail", "-f", "/dev/null"]
