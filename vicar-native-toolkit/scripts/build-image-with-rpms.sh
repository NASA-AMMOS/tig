#!/bin/bash
# Build VICAR Docker image with pre-built RPM packages
# This script builds an image that installs VICAR from RPMs instead of compiling from source

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "===== VICAR Docker Image Builder (with RPMs) ====="
echo "Project root: $PROJECT_ROOT"
echo ""

# Check if Dockerfile exists
if [ ! -f "$PROJECT_ROOT/docker/Dockerfile.with-rpms" ]; then
    echo "ERROR: Dockerfile not found: $PROJECT_ROOT/docker/Dockerfile.with-rpms"
    exit 1
fi

echo "===== Creating build context ====="

# Create temporary build context directory
BUILD_CONTEXT=$(mktemp -d -t vicar-rpm-build-XXXXXX)
echo "Build context: $BUILD_CONTEXT"

# Copy Dockerfile
cp "$PROJECT_ROOT/docker/Dockerfile.with-rpms" "$BUILD_CONTEXT/Dockerfile"
echo "✓ Copied Dockerfile"

# Check for and copy RPM repository configuration if available
echo ""
echo "===== Checking for RPM repository configuration ====="

RPM_REPO_CONFIG="$PROJECT_ROOT/docker/rpm-repo.repo"
if [ -f "$RPM_REPO_CONFIG" ]; then
    echo "✓ Found RPM repository configuration"
    
    # Check if repository config uses environment variables for authentication
    if grep -q '${ART_USER}' "$RPM_REPO_CONFIG" || grep -q '${ART_API_KEY}' "$RPM_REPO_CONFIG"; then
        echo "  Repository requires authentication credentials"
        
        # Check if environment variables are set
        if [ -z "$ART_USER" ] || [ -z "$ART_API_KEY" ]; then
            echo ""
            echo "❌ ERROR: Repository credentials not found"
            echo ""
            echo "   The rpm-repo.repo file requires authentication but environment"
            echo "   variables are not set. Please set the following:"
            echo ""
            echo "     export ART_USER=\"your-jpl-username\""
            echo "     export ART_API_KEY=\"your-artifactory-api-key\""
            echo ""
            echo "   Get your API key from:"
            echo "     https://artifactory.jpl.nasa.gov/ui/admin/artifactory/user_profile"
            echo ""
            echo "   Then run this script again."
            exit 1
        fi
        
        echo "  ✓ Credentials found: ART_USER=$ART_USER"
        echo "  ✓ Substituting credentials into repository configuration"
        
        # Check if envsubst is available
        if command -v envsubst &> /dev/null; then
            # Use envsubst for variable substitution
            envsubst '${ART_USER} ${ART_API_KEY}' < "$RPM_REPO_CONFIG" > "$BUILD_CONTEXT/rpm-repo.repo"
        else
            # Fallback: use sed for substitution
            sed -e "s/\${ART_USER}/$ART_USER/g" \
                -e "s/\${ART_API_KEY}/$ART_API_KEY/g" \
                "$RPM_REPO_CONFIG" > "$BUILD_CONTEXT/rpm-repo.repo"
        fi
    else
        # No variable substitution needed
        cp "$RPM_REPO_CONFIG" "$BUILD_CONTEXT/"
    fi
    
    echo "  Repository config will be added to container"
else
    echo "⚠️  No custom RPM repository configuration found"
    echo "   Looked for: $RPM_REPO_CONFIG"
    echo ""
    echo "   The build will attempt to install RPMs from system repositories."
    echo "   If VICAR RPMs are in a private repository, you need to either:"
    echo ""
    echo "   Option 1: Create a repository configuration file"
    echo "     Create: $RPM_REPO_CONFIG"
    echo "     Example content:"
    echo "       [vicar]"
    echo "       name=VICAR RPM Repository"
    echo "       baseurl=https://your-repo.example.com/vicar/el8/x86_64/"
    echo "       enabled=1"
    echo "       gpgcheck=0"
    echo ""
    echo "   Option 2: Copy RPM files directly into the image"
    echo "     Place .rpm files in: $PROJECT_ROOT/docker/rpms/"
    echo "     The Dockerfile will need to be modified to install from local files"
    echo ""
    
    # Check if user has RPM files available
    RPM_DIR="$PROJECT_ROOT/docker/rpms"
    if [ -d "$RPM_DIR" ] && [ "$(ls -A $RPM_DIR/*.rpm 2>/dev/null)" ]; then
        echo "✓ Found local RPM files in $RPM_DIR"
        echo "  Copying RPM files to build context..."
        mkdir -p "$BUILD_CONTEXT/rpms"
        cp "$RPM_DIR"/*.rpm "$BUILD_CONTEXT/rpms/"
        
        RPM_COUNT=$(ls -1 "$BUILD_CONTEXT/rpms"/*.rpm | wc -l)
        echo "  Copied $RPM_COUNT RPM files"
        echo ""
        echo "  NOTE: The Dockerfile will need to use 'dnf install /path/to/local/*.rpm'"
        echo "        instead of 'dnf install vicar-*' from repository"
    else
        echo "  No local RPM files found in: $RPM_DIR"
        echo ""
        echo "  Build will proceed, but may fail if RPMs are not available"
        echo "  in the system repositories or if network access is required."
    fi
    
    # Create empty placeholder repo file for Docker COPY (since no repo config exists)
    echo "# No custom repository configured" > "$BUILD_CONTEXT/rpm-repo.repo"
    echo "# System repositories will be used" >> "$BUILD_CONTEXT/rpm-repo.repo"
fi

echo ""
echo "===== Building Docker image ====="
echo "This should take 5-10 minutes (much faster than source compilation)..."
echo "Image name: vicar-tools:with-rpms"
echo ""

# RHEL/Oracle Linux base requires linux/amd64 (no ARM64 support for Oracle Linux 8.9)
DOCKER_PLATFORM="linux/amd64"
PLATFORM=$(uname -m)

if [ "$PLATFORM" = "arm64" ] || [ "$PLATFORM" = "aarch64" ]; then
    echo "NOTE: Building for linux/amd64 on ARM64 host (Apple Silicon)"
    echo "Oracle Linux 8.9 only supports amd64; image will run under emulation"
    echo "Performance may be reduced compared to native ARM64 images"
    echo ""
fi

echo "Building for platform: $DOCKER_PLATFORM"
echo ""
echo "Note: JPL CA certificates will be installed automatically for Artifactory access"
echo ""

# Build the image
cd "$BUILD_CONTEXT"
docker build \
    --platform "$DOCKER_PLATFORM" \
    --tag vicar-tools:with-rpms \
    --tag vicar-tools:rpm-latest \
    --progress=plain \
    .

BUILD_EXIT_CODE=$?

# Cleanup
echo ""
echo "===== Cleaning up build context ====="
rm -rf "$BUILD_CONTEXT"
echo "✓ Removed temporary build context"

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "===== Build successful! ====="
    echo ""
    echo "Image created: vicar-tools:with-rpms"
    echo "Also tagged as: vicar-tools:rpm-latest"
    echo ""
    echo "Next steps:"
    echo "  1. Test the image:"
    echo "     docker run --rm vicar-tools:with-rpms ls /usr/local/vicar/ndev/bin | head -20"
    echo ""
    echo "  2. Verify VICAR version:"
    echo "     docker run --rm vicar-tools:with-rpms rpm -qa | grep vicar"
    echo ""
    echo "  3. Use with vicar-native-toolkit:"
    echo "     cd $PROJECT_ROOT"
    echo "     # Update docker-compose.yml to use vicar-tools:with-rpms"
    echo "     direnv allow"
    echo ""
    echo "  4. Or run interactively:"
    echo "     docker run -it --rm vicar-tools:with-rpms bash"
    echo ""
    
    # Show image size
    echo "Image size:"
    docker images vicar-tools:with-rpms --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}"
    
    # Show installed RPM packages
    echo ""
    echo "Installed VICAR RPM packages:"
    docker run --rm vicar-tools:with-rpms rpm -qa | grep -i vicar || echo "  (Could not query RPMs)"
    
else
    echo ""
    echo "===== Build failed! ====="
    echo "Exit code: $BUILD_EXIT_CODE"
    echo ""
    echo "Troubleshooting:"
    echo "  - Check Docker logs above for errors"
    echo "  - Verify RPM repository is accessible (if using remote repo)"
    echo "  - Ensure RPM files exist (if using local files)"
    echo "  - Check that package names are correct: vicar-m20-g87-all, vicar-external-*"
    echo "  - Verify you have enough disk space (~5GB)"
    echo "  - Check that Docker has sufficient memory (recommend 4GB+)"
    echo ""
    echo "Common issues:"
    echo "  1. RPMs not found: Configure RPM repository or provide local RPM files"
    echo "  2. Wrong package names: Check available packages with 'dnf search vicar'"
    echo "  3. Dependency issues: Some RPMs may require additional system packages"
    exit $BUILD_EXIT_CODE
fi
