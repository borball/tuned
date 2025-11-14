#!/bin/bash
# Remote installer for enhanced tuned-adm
# Usage: curl -sSL https://raw.githubusercontent.com/USER/REPO/TAG/install.sh | bash
# Or with custom tag: curl -sSL https://raw.githubusercontent.com/USER/REPO/TAG/install.sh | TAG=v1.0 bash

set -e

# Configuration
GITHUB_USER="${GITHUB_USER:-borball}"
GITHUB_REPO="${GITHUB_REPO:-tuned}"
TAG="${TAG:-master}"  # Use 'main' branch by default, override with TAG=v1.0
BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${TAG}"

# Installation directories
USER_BIN="$HOME/.local/bin"
TUNED_LIB="$HOME/.local/lib/tuned-enhanced"
TUNED_ADMIN_DIR="$TUNED_LIB/tuned/admin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() { echo -e "${BLUE}ℹ${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Download file with error handling
download_file() {
    local url="$1"
    local output="$2"
    local description="$3"
    
    info "Downloading $description..."
    if command_exists curl; then
        if ! curl -fsSL "$url" -o "$output"; then
            error "Failed to download $description from $url"
            return 1
        fi
    elif command_exists wget; then
        if ! wget -q "$url" -O "$output"; then
            error "Failed to download $description from $url"
            return 1
        fi
    else
        error "Neither curl nor wget found. Please install one of them."
        return 1
    fi
    success "Downloaded $description"
}

echo "=============================================================================="
echo "Enhanced tuned-adm Remote Installer"
echo "=============================================================================="
echo ""
info "Installing from: ${GITHUB_USER}/${GITHUB_REPO}@${TAG}"
echo ""

# Check prerequisites
info "Checking prerequisites..."
if ! command_exists python3; then
    error "Python 3 is required but not found"
    exit 1
fi
success "Python 3 found: $(python3 --version)"

# Check if tuned is installed
if ! command_exists tuned-adm || [ ! -d "/usr/lib/tuned" ]; then
    warn "System tuned package not found. Enhanced features will work with repository profiles only."
    info "To install tuned: dnf install tuned (RHEL/Fedora) or apt install tuned (Debian/Ubuntu)"
fi

# Create directories
info "Creating installation directories..."
mkdir -p "$USER_BIN"
mkdir -p "$TUNED_ADMIN_DIR"
success "Directories created"

# Download files
echo ""
info "Downloading enhanced tuned-adm files..."

# Download main script
if ! download_file "${BASE_URL}/tuned-adm.py" "$TUNED_LIB/tuned-adm.py" "tuned-adm.py"; then
    error "Installation failed"
    exit 1
fi

# Download admin module
if ! download_file "${BASE_URL}/tuned/admin/admin.py" "$TUNED_ADMIN_DIR/admin.py" "admin.py"; then
    error "Installation failed"
    exit 1
fi

# Create minimal module structure  
info "Creating module structure..."
mkdir -p "$TUNED_ADMIN_DIR"

# Don't create tuned/__init__.py - let system tuned handle that
# Just create admin/__init__.py
cat > "$TUNED_ADMIN_DIR/__init__.py" << 'ADMININITEOF'
from .admin import Admin
__all__ = ["Admin"]
ADMININITEOF

success "Module structure created"

# Check if system tuned Python module is available
info "Checking for system tuned module..."
SYSTEM_TUNED_PATH=""
if python3 -c "import tuned" 2>/dev/null; then
    SYSTEM_TUNED_PATH=$(python3 -c "import tuned, os; print(os.path.dirname(tuned.__file__))" 2>/dev/null)
    success "System tuned module found at: $SYSTEM_TUNED_PATH"
    USE_SYSTEM_TUNED=1
else
    warn "System tuned module not found"
    warn "The enhanced version requires system tuned to be installed"
    error "Please install tuned first: dnf install tuned (or apt install tuned)"
    exit 1
fi

# Make scripts executable
chmod +x "$TUNED_LIB/tuned-adm.py"

# Create wrapper script
info "Creating wrapper script..."
cat > "$USER_BIN/tuned-adm" << EOF
#!/usr/bin/python3 -Es
# Enhanced tuned-adm with profile hierarchy viewer
# Installed from: ${GITHUB_USER}/${GITHUB_REPO}@${TAG}
# Location: ~/.local/bin/tuned-adm (user version)
# System version remains at /usr/sbin/tuned-adm

import sys
import os

TUNED_LIB = '$TUNED_LIB'

# CRITICAL: Add our enhanced path FIRST before any imports
sys.path.insert(0, TUNED_LIB)

# Import system tuned to get base package
import tuned

# Patch tuned package's __path__ to look in our directory FIRST
# This ensures tuned.admin imports come from our enhanced version
if hasattr(tuned, '__path__'):
    # Insert our tuned directory at the beginning of the package path
    tuned.__path__.insert(0, os.path.join(TUNED_LIB, 'tuned'))

# Clear any cached admin modules
for mod in list(sys.modules.keys()):
    if mod.startswith('tuned.admin'):
        del sys.modules[mod]

# Now when tuned-adm.py imports tuned.admin, it will get our enhanced version
# Execute the enhanced tuned-adm.py
os.chdir(TUNED_LIB)
exec(open(os.path.join(TUNED_LIB, 'tuned-adm.py')).read(), {'__name__': '__main__', '__file__': os.path.join(TUNED_LIB, 'tuned-adm.py')})
EOF

chmod +x "$USER_BIN/tuned-adm"
success "Wrapper script created: $USER_BIN/tuned-adm"

# Check if ~/.local/bin is in PATH
echo ""
if [[ ":$PATH:" != *":$USER_BIN:"* ]]; then
    warn "$USER_BIN is not in PATH"
    
    # Determine shell config file
    if [ -n "$ZSH_VERSION" ]; then
        SHELL_RC="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        SHELL_RC="$HOME/.bashrc"
    else
        SHELL_RC="$HOME/.profile"
    fi
    
    info "Adding $USER_BIN to PATH in $SHELL_RC"
    if ! grep -q "/.local/bin" "$SHELL_RC" 2>/dev/null; then
        echo "" >> "$SHELL_RC"
        echo "# Added by enhanced tuned-adm installer" >> "$SHELL_RC"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
        success "Added to $SHELL_RC"
        warn "Run: source $SHELL_RC"
        warn "Or open a new terminal for PATH changes to take effect"
    else
        info "$USER_BIN already in PATH config"
    fi
else
    success "$USER_BIN is in PATH"
fi

# Verify installation
echo ""
info "Verifying installation..."
if [ -x "$USER_BIN/tuned-adm" ]; then
    if "$USER_BIN/tuned-adm" --version &>/dev/null; then
        success "Enhanced tuned-adm is working!"
    else
        success "Enhanced tuned-adm installed (version check requires tuned daemon)"
    fi
    
    if "$USER_BIN/tuned-adm" profile_info --help 2>&1 | grep -q "verbose"; then
        success "--verbose flag is available!"
    fi
else
    error "Installation verification failed"
    exit 1
fi

echo ""
echo "=============================================================================="
echo "Installation Complete!"
echo "=============================================================================="
echo ""
warn "IMPORTANT: Clear shell cache to use the new command:"
echo "  hash -r"
echo "  # Or open a new terminal"
echo ""
echo "Installed to:"
echo "  Enhanced: $USER_BIN/tuned-adm"
echo "  Library:  $TUNED_LIB"
echo "  System:   /usr/sbin/tuned-adm (unchanged)"
echo ""
echo "Usage:"
echo "  tuned-adm profile_info <profile> --verbose    # Enhanced version"
echo "  /usr/sbin/tuned-adm profile_info <profile>    # System version"
echo ""
echo "Example:"
echo "  tuned-adm profile_info network-latency --verbose"
echo ""
echo "Uninstall:"
echo "  rm -rf $USER_BIN/tuned-adm $TUNED_LIB"
echo ""
echo "For more information, see:"
echo "  https://github.com/${GITHUB_USER}/${GITHUB_REPO}"
echo ""

