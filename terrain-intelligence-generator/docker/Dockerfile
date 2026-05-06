# Terrain Intelligence Generator - Open Source Build
# Uses pre-built VICAR binaries from GitHub releases
# Based on Oracle Linux 8 (RHEL-compatible)

FROM oraclelinux:8

LABEL org.opencontainers.image.title="Terrain Intelligence Generator"
LABEL org.opencontainers.image.description="Open source distribution of VICAR-based terrain intelligence generation tools"
LABEL org.opencontainers.image.version="5.0-opensource"
LABEL org.opencontainers.image.source="https://github.com/NASA-AMMOS/VICAR"

# Set VICAR environment
ENV V2TOP=/usr/local/vicar/dev
ENV WORKSPACE=/usr/local/vicar
ENV VICSYS=DEVELOPMENT
ENV SHELL=/bin/bash
ENV PATH="${V2TOP}/p2/lib/x86-64-linx:${V2TOP}/tae53/bin/x86_64_linx:${PATH}"
ENV LD_LIBRARY_PATH="${V2TOP}/olb/x86-64-linx:${V2TOP}/p2/lib/x86-64-linx:${V2TOP}/mars/lib/x86-64-linx:${LD_LIBRARY_PATH}"

# Enable PowerTools (CodeReady Builder) for additional packages
RUN dnf install -y dnf-plugins-core && \
    dnf config-manager --enable ol8_codeready_builder

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
    # Java runtime (headless for smaller size)
    java-1.8.0-openjdk-headless \
    # Python runtime
    python39 \
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
    curl \
    tar \
    gzip \
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

# Download and extract pre-built VICAR binaries from GitHub releases
ARG VICAR_VERSION=5.0
ARG BINARIES_FILE=vicar_open_bin_x86-64-linx_5.0.tar.gz
ARG EXTERNAL_FILE=vicar_open_ext_x86-64-linx_5.0.tar.gz

WORKDIR /tmp

# Download and extract VICAR binaries
RUN echo "Downloading and extracting VICAR binaries..." && \
    curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/${VICAR_VERSION}/${BINARIES_FILE}" | tar -zxf - && \
    EXTRACTED_DIR=$(ls -d vicar_open_bin_* 2>/dev/null | head -1) && \
    if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR" ]; then \
        echo "Found extracted directory: $EXTRACTED_DIR"; \
        # Check if there's a nested vicar_open_5.0 directory inside the bin directory
        if [ -d "$EXTRACTED_DIR/vicar_open_5.0" ]; then \
            echo "Found nested VICAR directory: $EXTRACTED_DIR/vicar_open_5.0"; \
            echo "Flattening structure - moving contents directly to ${WORKSPACE}/dev/"; \
            cp -r "$EXTRACTED_DIR/vicar_open_5.0"/* ${WORKSPACE}/dev/ && \
            echo "✓ VICAR binaries installed (flattened from nested structure)"; \
        else \
            echo "Moving $EXTRACTED_DIR contents to ${WORKSPACE}/dev/"; \
            cp -r "$EXTRACTED_DIR"/* ${WORKSPACE}/dev/ && \
            echo "✓ VICAR binaries installed"; \
        fi && \
        rm -rf "$EXTRACTED_DIR"; \
    else \
        echo "ERROR: Could not find extracted binaries directory" && exit 1; \
    fi && \
    echo "Verifying flattened structure..." && \
    ls -la ${WORKSPACE}/dev/ && \
    if [ -d "${WORKSPACE}/dev/p2" ] && [ -d "${WORKSPACE}/dev/tae53" ]; then \
        echo "✓ Structure verification passed - p2 and tae53 directories found directly under dev/"; \
    else \
        echo "ERROR: Expected directories not found. Directory structure:"; \
        find ${WORKSPACE}/dev -maxdepth 2 -type d; \
        exit 1; \
    fi

# Download and extract VICAR external libraries
RUN echo "Downloading and extracting VICAR external libraries..." && \
    curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/${VICAR_VERSION}/${EXTERNAL_FILE}" | tar -zxf - && \
    EXTRACTED_DIR=$(ls -d vicar_open_ext_* 2>/dev/null | head -1) && \
    if [ -n "$EXTRACTED_DIR" ] && [ -d "$EXTRACTED_DIR" ]; then \
        echo "Found extracted directory: $EXTRACTED_DIR"; \
        # Check if there's content to flatten
        CONTENT_COUNT=$(find "$EXTRACTED_DIR" -maxdepth 1 -mindepth 1 | wc -l); \
        if [ "$CONTENT_COUNT" -eq 1 ]; then \
            # Single subdirectory - flatten it
            SUBDIR=$(find "$EXTRACTED_DIR" -maxdepth 1 -mindepth 1 -type d | head -1); \
            if [ -n "$SUBDIR" ]; then \
                echo "Flattening external libraries from nested structure"; \
                mkdir -p ${WORKSPACE}/external && \
                cp -r "$SUBDIR"/* ${WORKSPACE}/external/ && \
                echo "✓ External libraries installed (flattened)"; \
            else \
                mkdir -p ${WORKSPACE}/external && \
                cp -r "$EXTRACTED_DIR"/* ${WORKSPACE}/external/ && \
                echo "✓ External libraries installed"; \
            fi; \
        else \
            echo "Moving $EXTRACTED_DIR contents to ${WORKSPACE}/external/"; \
            mkdir -p ${WORKSPACE}/external && \
            cp -r "$EXTRACTED_DIR"/* ${WORKSPACE}/external/ && \
            echo "✓ External libraries installed"; \
        fi && \
        rm -rf "$EXTRACTED_DIR"; \
    else \
        echo "ERROR: Could not find extracted externals directory" && exit 1; \
    fi

# Download and extract VISOR calibration files (open source missions)
RUN echo "Downloading and extracting VISOR calibration files..." && \
    mkdir -p ${WORKSPACE}/visor_data/calib && \
    curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/${VICAR_VERSION}/visor_calibration_20230608_phx.tar.gz" | \
        tar -zxf - -C ${WORKSPACE}/visor_data/calib && \
    echo "✓ Extracted Phoenix calibration files" && \
    curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/${VICAR_VERSION}/visor_calibration_20230608_mer.tar.gz" | \
        tar -zxf - -C ${WORKSPACE}/visor_data/calib && \
    echo "✓ Extracted MER calibration files"

# Download and extract VISOR sample data
RUN echo "Downloading and extracting VISOR sample data..." && \
    mkdir -p ${WORKSPACE}/visor_data/samples && \
    curl -L "https://github.com/NASA-AMMOS/VICAR/releases/download/${VICAR_VERSION}/visor_sample_data_20230623.tar.gz" | \
        tar -zxf - -C ${WORKSPACE}/visor_data/samples && \
    echo "✓ Extracted VISOR sample data"

# Set environment variables for VISOR data
ENV VISOR_CALIB=${WORKSPACE}/visor_data/calib
ENV VISOR_SAMPLES=${WORKSPACE}/visor_data/samples

WORKDIR /workspace

# Create symbolic links for common VICAR commands in /usr/local/bin
RUN ARCH_DIR="x86-64-linx" && \
    TAE_ARCH_DIR="x86_64_linx" && \
    echo "Creating wrapper scripts for VICAR commands..." && \
    echo "V2TOP=${V2TOP}" && \
    echo "Checking for directories:" && \
    ls -la ${V2TOP}/ && \
    # Build comprehensive library path
    VICAR_LIB_PATH="${V2TOP}/olb/$ARCH_DIR:${V2TOP}/mars/lib/$ARCH_DIR" && \
    for extlib in ${WORKSPACE}/external/*/v*/$ARCH_DIR/lib ${WORKSPACE}/external/*/v*/$ARCH_DIR/lib64 ${WORKSPACE}/external/*/v*/$ARCH_DIR; do \
        if [ -d "$extlib" ]; then \
            VICAR_LIB_PATH="$VICAR_LIB_PATH:$extlib"; \
        fi; \
    done && \
    echo "Built library path with $(echo $VICAR_LIB_PATH | tr ':' '\n' | wc -l) directories" && \
    # Create wrappers for VICAR p2 programs
    if [ -d "${V2TOP}/p2/lib/$ARCH_DIR" ]; then \
        echo "Found p2 directory: ${V2TOP}/p2/lib/$ARCH_DIR"; \
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
    else \
        echo "⚠ p2 directory not found at ${V2TOP}/p2/lib/$ARCH_DIR"; \
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
    else \
        echo "⚠ TAE directory not found at ${V2TOP}/tae53/bin/$TAE_ARCH_DIR"; \
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
    else \
        echo "⚠ MARS directory not found at ${V2TOP}/mars/lib/$ARCH_DIR"; \
    fi && \
    echo "Wrapper creation complete"

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
    echo "export VISOR_CALIB=${WORKSPACE}/visor_data/calib" >> /etc/profile.d/vicar.sh && \
    echo "export VISOR_SAMPLES=${WORKSPACE}/visor_data/samples" >> /etc/profile.d/vicar.sh && \
    echo "export LD_LIBRARY_PATH=$VICAR_LIB_PATH:\$LD_LIBRARY_PATH" >> /etc/profile.d/vicar.sh && \
    echo "export PATH=${V2TOP}/tae53/bin:${V2TOP}/bin:\$PATH" >> /etc/profile.d/vicar.sh && \
    chmod +x /etc/profile.d/vicar.sh

# Install Python pip for additional tools
RUN dnf install -y python39-pip && \
    dnf clean all && \
    rm -rf /var/cache/dnf /var/cache/yum

# Install Python dependencies for vicario (VICAR I/O converter)
RUN python3 -m pip install --no-cache-dir --upgrade pip && \
    python3 -m pip install --no-cache-dir Pillow>=9.0.0

# Copy vicario script (VICAR to PNG/JPEG/TIFF converter)
COPY scripts/vicario /usr/local/bin/vicario
RUN chmod +x /usr/local/bin/vicario

# Verify VICAR installation
RUN echo "===== VICAR Installation Verification =====" && \
    echo "V2TOP: ${V2TOP}" && \
    echo "" && \
    if [ -d "${V2TOP}" ]; then \
        echo "✓ Found VICAR at ${V2TOP}"; \
        echo "Contents:"; \
        ls -la ${V2TOP}/ | head -20; \
        echo ""; \
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
    test -x /usr/local/bin/vicario && echo "✓ vicario installed" || echo "✗ vicario not found" && \
    python3 -c "import PIL; print('✓ Pillow version:', PIL.__version__)" || echo "✗ Pillow not installed" && \
    echo "" && \
    echo "Checking VISOR data:" && \
    if [ -d "${WORKSPACE}/visor_data/calib" ]; then \
        CALIB_COUNT=$(find ${WORKSPACE}/visor_data/calib -type f 2>/dev/null | wc -l); \
        echo "✓ VISOR calibration files: $CALIB_COUNT files"; \
    fi && \
    if [ -d "${WORKSPACE}/visor_data/samples" ]; then \
        SAMPLE_COUNT=$(find ${WORKSPACE}/visor_data/samples -type f 2>/dev/null | wc -l); \
        echo "✓ VISOR sample data: $SAMPLE_COUNT files"; \
    fi

# Create entrypoint script
RUN echo '#!/bin/bash' > /usr/local/bin/docker-entrypoint.sh && \
    echo 'source /etc/profile.d/vicar.sh 2>/dev/null || true' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'exec "$@"' >> /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

# Set working directory
WORKDIR /workspace

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Display installation summary
RUN echo "===== Terrain Intelligence Generator Installation Complete =====" && \
    echo "V2TOP: ${V2TOP}" && \
    echo "Source: Pre-built binaries from https://github.com/NASA-AMMOS/VICAR/releases" && \
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
    echo "VISOR data available at:" && \
    echo "  Calibrations: ${WORKSPACE}/visor_data/calib" && \
    echo "  Sample data:  ${WORKSPACE}/visor_data/samples"

# Keep container running
CMD ["tail", "-f", "/dev/null"]
