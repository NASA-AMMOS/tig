#!/bin/bash
# macOS Setup Script for VICAR Native Toolkit
# This script installs all necessary dependencies for macOS (M1/M2/Intel)

set -e

echo "=========================================="
echo "VICAR Native Toolkit - macOS Setup"
echo "=========================================="
echo ""

# Check if running on macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "❌ Error: This script is for macOS only"
    exit 1
fi

# Check for Homebrew
echo "📦 Checking for Homebrew..."
if ! command -v brew &>/dev/null; then
    echo "❌ Homebrew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for Apple Silicon
    if [[ "$(uname -m)" == "arm64" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    echo "✅ Homebrew is installed"
fi

# Install direnv
echo ""
echo "📦 Installing direnv..."
if ! command -v direnv &>/dev/null; then
    brew install direnv
    echo "✅ direnv installed"
else
    echo "✅ direnv already installed"
fi

# Install GNU coreutils (for realpath)
echo ""
echo "📦 Installing GNU coreutils..."
if ! command -v grealpath &>/dev/null; then
    brew install coreutils
    echo "✅ GNU coreutils installed"
else
    echo "✅ GNU coreutils already installed"
fi

# Install XQuartz
echo ""
echo "📦 Installing XQuartz (X11 for macOS)..."
if ! brew list --cask xquartz &>/dev/null; then
    brew install --cask xquartz
    echo "✅ XQuartz installed"
    echo ""
    echo "⚠️  IMPORTANT: You must REBOOT your Mac after first-time XQuartz installation!"
    echo ""
    read -p "Press Enter to continue after reboot, or Ctrl+C to exit and reboot now..."
else
    echo "✅ XQuartz already installed"
fi

# Check if Docker Desktop is installed
echo ""
echo "🐳 Checking for Docker Desktop..."
if ! command -v docker &>/dev/null; then
    echo "❌ Docker Desktop not found!"
    echo ""
    echo "Please install Docker Desktop manually:"
    echo "  1. Visit: https://www.docker.com/products/docker-desktop"
    echo "  2. Download Docker Desktop for Mac (Apple Silicon or Intel)"
    echo "  3. Install and start Docker Desktop"
    echo "  4. Re-run this setup script"
    exit 1
else
    echo "✅ Docker Desktop is installed"
    
    # Check if Docker is running
    if ! docker info &>/dev/null; then
        echo "⚠️  Docker Desktop is not running. Please start it and try again."
        exit 1
    fi
fi

# Configure direnv hook for zsh (default shell on macOS)
echo ""
echo "🔧 Configuring direnv for zsh..."
if ! grep -q 'direnv hook zsh' ~/.zshrc 2>/dev/null; then
    echo '' >> ~/.zshrc
    echo '# direnv hook for VICAR Native Toolkit' >> ~/.zshrc
    echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
    echo "✅ direnv hook added to ~/.zshrc"
else
    echo "✅ direnv hook already configured"
fi

# Configure XQuartz
echo ""
echo "🔧 Configuring XQuartz..."

# Enable network clients
defaults write org.xquartz.X11 nolisten_tcp -bool false

# Create xinitrc.d directory for auto-config
mkdir -p ~/.xinitrc.d

# Create xhost config script
cat > ~/.xinitrc.d/xhost-config.sh <<'EOF'
#!/bin/sh
# Auto-allow localhost connections to X11
xhost +localhost
EOF
chmod +x ~/.xinitrc.d/xhost-config.sh

echo "✅ XQuartz configured to allow network connections"

# Verify Docker Desktop file sharing
echo ""
echo "🔧 Checking Docker Desktop file sharing settings..."
echo "Docker Desktop needs permission to access your project files."
echo ""
echo "Please verify in Docker Desktop:"
echo "  Settings → Resources → File Sharing"
echo "  Ensure these paths are listed:"
echo "    - /Users"
echo "    - /tmp"
echo "    - /private"
echo ""

# Start XQuartz if not running
echo ""
echo "🚀 Starting XQuartz..."
if ! pgrep -q Xquartz && ! pgrep -q X11; then
    open -a XQuartz
    sleep 3
    xhost +localhost 2>/dev/null || echo "Note: xhost will be available after XQuartz fully starts"
    echo "✅ XQuartz started"
else
    echo "✅ XQuartz is already running"
    xhost +localhost 2>/dev/null || true
fi

# Summary
echo ""
echo "=========================================="
echo "✅ macOS Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Make sure Docker Desktop is running"
echo "  2. Restart your terminal (or run: source ~/.zshrc)"
echo "  3. Build the Docker image: ./scripts/build-image.sh"
echo "  4. Enter the toolkit directory: cd vicar-native-toolkit"
echo "  5. Allow direnv: direnv allow"
echo ""
echo "Notes:"
echo "  - XQuartz must be running for GUI applications"
echo "  - On first use, XQuartz may prompt for accessibility permissions"
echo "  - If you just installed XQuartz for the first time, REBOOT is required!"
echo ""
