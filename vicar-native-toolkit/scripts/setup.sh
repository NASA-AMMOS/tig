#!/bin/bash
# Master setup script for VICAR Native Toolkit
# Detects platform and runs appropriate setup

set -e

echo "=========================================="
echo "VICAR Native Toolkit - Automated Setup"
echo "=========================================="
echo ""

# Detect platform
HOST_OS="$(uname -s)"
ARCH="$(uname -m)"

echo "Detected platform: ${HOST_OS} (${ARCH})"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run platform-specific setup
if [[ "${HOST_OS}" == "Darwin" ]]; then
    echo "Running macOS setup..."
    bash "${SCRIPT_DIR}/setup-macos.sh"
elif [[ "${HOST_OS}" == "Linux" ]]; then
    echo "Running Linux setup..."
    bash "${SCRIPT_DIR}/setup-linux.sh"
else
    echo "❌ Unsupported platform: ${HOST_OS}"
    exit 1
fi

# Check if we should continue to build
echo ""
read -p "Setup complete. Build Docker image now? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "${SCRIPT_DIR}/build-image.sh"
    
    echo ""
    echo "=========================================="
    echo "✅ All Done!"
    echo "=========================================="
    echo ""
    echo "To start using VICAR Native Toolkit:"
    echo "  1. Restart your terminal (or source your shell config)"
    
    if [[ "${HOST_OS}" == "Darwin" ]]; then
        echo "  2. Make sure XQuartz is running"
        echo "  3. cd $(dirname ${SCRIPT_DIR})"
    else
        echo "  2. cd $(dirname ${SCRIPT_DIR})"
    fi
    
    echo "  3. direnv allow"
    echo "  4. toolkit-shell  # to enter the container"
    echo ""
else
    echo ""
    echo "Skipping Docker image build."
    echo "Run './scripts/build-image.sh' when ready."
fi
