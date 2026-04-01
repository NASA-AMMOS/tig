#!/bin/bash
# Linux Setup Script for VICAR Native Toolkit
# Tested on Ubuntu/Debian-based systems

set -e

echo "=========================================="
echo "VICAR Native Toolkit - Linux Setup"
echo "=========================================="
echo ""

# Check if running on Linux
if [[ "$(uname -s)" != "Linux" ]]; then
    echo "❌ Error: This script is for Linux only"
    exit 1
fi

# Detect package manager
if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
    PKG_INSTALL="sudo apt-get install -y"
    PKG_UPDATE="sudo apt-get update"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
    PKG_INSTALL="sudo dnf install -y"
    PKG_UPDATE="sudo dnf check-update"
elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
    PKG_INSTALL="sudo yum install -y"
    PKG_UPDATE="sudo yum check-update"
else
    echo "❌ Unsupported package manager. Please install dependencies manually."
    exit 1
fi

echo "Detected package manager: ${PKG_MANAGER}"
echo ""

# Update package lists
echo "📦 Updating package lists..."
${PKG_UPDATE} || true

# Install direnv
echo ""
echo "📦 Installing direnv..."
if ! command -v direnv &>/dev/null; then
    ${PKG_INSTALL} direnv
    echo "✅ direnv installed"
else
    echo "✅ direnv already installed"
fi

# Install Docker if not present
echo ""
echo "🐳 Checking for Docker..."
if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    
    if [[ "${PKG_MANAGER}" == "apt" ]]; then
        # Docker installation for Ubuntu/Debian
        ${PKG_INSTALL} ca-certificates curl gnupg lsb-release
        
        # Add Docker's official GPG key
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Set up Docker repository
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        sudo apt-get update
        ${PKG_INSTALL} docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        # For other distros, use their native Docker packages
        ${PKG_INSTALL} docker
    fi
    
    # Start Docker service
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    echo "✅ Docker installed"
    echo "⚠️  You need to log out and log back in for Docker group membership to take effect"
else
    echo "✅ Docker already installed"
    
    # Check if Docker is running
    if ! docker info &>/dev/null; then
        echo "🔄 Starting Docker service..."
        sudo systemctl start docker
    fi
fi

# Ensure user is in docker group
if ! groups | grep -q docker; then
    echo ""
    echo "⚠️  Adding user to docker group..."
    sudo usermod -aG docker $USER
    echo "You need to log out and log back in for this to take effect"
fi

# Install X11 utilities
echo ""
echo "📦 Installing X11 utilities..."
if [[ "${PKG_MANAGER}" == "apt" ]]; then
    ${PKG_INSTALL} x11-xserver-utils xauth
else
    ${PKG_INSTALL} xorg-x11-server-utils xauth
fi

# Configure X11 for Docker
echo ""
echo "🔧 Configuring X11 for Docker..."
if ! grep -q "xhost +local:docker" ~/.bashrc 2>/dev/null; then
    echo '' >> ~/.bashrc
    echo '# Allow Docker containers to access X11 display' >> ~/.bashrc
    echo 'xhost +local:docker 2>/dev/null || true' >> ~/.bashrc
    echo "✅ X11 configuration added to ~/.bashrc"
fi

# Run xhost command now
xhost +local:docker 2>/dev/null || echo "Note: Run 'xhost +local:docker' after X11 is available"

# Configure direnv hook for bash
echo ""
echo "🔧 Configuring direnv for bash..."
if ! grep -q 'direnv hook bash' ~/.bashrc 2>/dev/null; then
    echo '' >> ~/.bashrc
    echo '# direnv hook for VICAR Native Toolkit' >> ~/.bashrc
    echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
    echo "✅ direnv hook added to ~/.bashrc"
else
    echo "✅ direnv hook already configured"
fi

# Summary
echo ""
echo "=========================================="
echo "✅ Linux Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. If Docker was just installed, log out and log back in"
echo "  2. Restart your terminal (or run: source ~/.bashrc)"
echo "  3. Build the Docker image: ./scripts/build-image.sh"
echo "  4. Enter the toolkit directory: cd vicar-native-toolkit"
echo "  5. Allow direnv: direnv allow"
echo ""
echo "Notes:"
echo "  - Make sure X11 display is available (DISPLAY environment variable)"
echo "  - Run 'xhost +local:docker' before using GUI applications"
echo ""
