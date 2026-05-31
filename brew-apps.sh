#!/usr/bin/env bash

# MacSetup Homebrew Cask Applications Installation Script
# Installs GUI applications using Homebrew Cask

set -euo pipefail  # Exit on error, undefined vars, pipe failures

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f "$SCRIPT_DIR/lib.sh" ]]; then
    echo "Error: missing $SCRIPT_DIR/lib.sh (required by this script)" >&2
    exit 1
fi
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Check if Homebrew is installed
check_homebrew() {
    if ! command -v brew &> /dev/null; then
        log_error "Homebrew is not installed. Please run brew.sh first."
        exit 1
    fi
    log_info "Homebrew found, proceeding with cask installations..."
}

# Install cask applications
install_cask_apps() {
    log_info "Installing GUI applications via Homebrew Cask..."
    
    # Define cask applications with categories
    # Web Browsers
    local browsers=(
        "firefox"                # Mozilla Firefox
        "google-chrome"          # Google Chrome
    )
    
    # Development Tools
    local dev_tools=(
        "claude"                 # Anthropic Claude Code Editor
        "docker"                 # Docker Desktop
        "github"                 # GitHub Desktop
        "iterm2"                 # Terminal replacement
        "warp"                   # Warp terminal
        "postman"                # API development environment
        "visual-studio-code"     # Code editor
    )
    
    # Creative & Productivity
    local creative_tools=(
        "adobe-creative-cloud"   # Adobe Creative Suite
        "moom"                   # Window management
    )
    
    # System Utilities
    local utilities=(
        "balenaetcher"           # USB/SD card imaging
        "cloudflare-warp"        # Cloudflare WARP VPN
        "istat-menus"            # System monitoring
        "jdownloader"            # Download manager
        "nordvpn"                # NordVPN client
        "remote-desktop-manager" # Remote connection manager
    )
    
    # Media & Entertainment
    local media_apps=(
        "obs"                    # OBS Studio - streaming/recording
        "plex"                   # Media server
        "plexamp"                # Music player
        "vlc"                    # Video player
    )
    
    # Communication
    local communication=(
        "signal"                 # Secure messaging
    )
    
    # Enterprise/Work
    local enterprise=(
        "vmware-horizon-client"  # VMware remote desktop
    )
    
    # Combine all arrays
    local all_casks=()
    all_casks+=("${browsers[@]}")
    all_casks+=("${dev_tools[@]}")
    all_casks+=("${creative_tools[@]}")
    all_casks+=("${utilities[@]}")
    all_casks+=("${media_apps[@]}")
    all_casks+=("${communication[@]}")
    all_casks+=("${enterprise[@]}")
    
    # Install casks individually for better error handling
    local failed_casks=()
    local successful_casks=()
    
    for cask in "${all_casks[@]}"; do
        log_info "Installing $cask..."
        local error_output
        if error_output=$(brew install --cask "$cask" 2>&1); then
            log_success "Installed: $cask"
            successful_casks+=("$cask")
        else
            log_error "Failed to install: $cask"
            echo "$error_output" | tail -5 | sed 's/^/    /'
            failed_casks+=("$cask")
        fi
    done
    
    # Summary
    log_info "Installation Summary:"
    log_success "Successfully installed ${#successful_casks[@]} applications"
    
    if [ ${#failed_casks[@]} -gt 0 ]; then
        log_warning "Failed to install ${#failed_casks[@]} applications:"
        for failed in "${failed_casks[@]}"; do
            echo "  - $failed"
        done
        log_info "You can try installing failed applications manually with: brew install --cask <app-name>"
    fi
}

# Install PowerShell via direct .pkg download from GitHub releases.
# The homebrew-cask tap removed 'powershell', and the Microsoft tap formula
# currently has a broken `depends_on macos: :high_sierra` call that modern
# Homebrew rejects — so we go straight to the source.
install_powershell() {
    log_info "Installing PowerShell..."

    if command -v pwsh &>/dev/null; then
        log_info "PowerShell already installed at $(command -v pwsh), skipping"
        return 0
    fi

    # Resolve latest stable release tag from GitHub
    local latest_tag
    latest_tag=$(curl -fsSL "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null)

    if [[ -z "$latest_tag" ]]; then
        log_error "Could not determine latest PowerShell version from GitHub API"
        log_info "Install manually: https://github.com/PowerShell/PowerShell/releases/latest"
        return 1
    fi

    local version="${latest_tag#v}"  # strip leading 'v'
    local arch
    arch=$(uname -m)

    local pkg_name
    if [[ "$arch" == "arm64" ]]; then
        pkg_name="powershell-${version}-osx-arm64.pkg"
    else
        pkg_name="powershell-${version}-osx-x64.pkg"
    fi

    local url="https://github.com/PowerShell/PowerShell/releases/download/${latest_tag}/${pkg_name}"
    local tmp_pkg="/tmp/${pkg_name}"

    log_info "Downloading PowerShell ${version} (${arch})..."
    if ! curl -fsSL --progress-bar "$url" -o "$tmp_pkg"; then
        log_error "Failed to download PowerShell from: $url"
        return 1
    fi

    log_info "Installing package (requires sudo)..."
    if sudo installer -pkg "$tmp_pkg" -target /; then
        log_success "Installed: PowerShell ${version}"
        rm -f "$tmp_pkg"
    else
        log_error "Failed to install PowerShell package"
        rm -f "$tmp_pkg"
        return 1
    fi
}

# Setup PowerShell modules (separated from main cask installation)
setup_powershell_modules() {
    log_info "Setting up PowerShell modules..."
    
    # Check if PowerShell is available
    if ! command -v pwsh &> /dev/null; then
        log_warning "PowerShell not found. Make sure it was installed successfully first."
        return 1
    fi
    
    log_info "Setting PSGallery as trusted..."
    pwsh -Command "Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted" || true

    log_info "Installing VMware PowerCLI module..."
    if pwsh -Command "Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force -AllowClobber -Repository PSGallery"; then
        log_success "VMware PowerCLI module installed successfully"
    else
        log_error "Failed to install VMware PowerCLI module"
        log_info "You can retry manually: pwsh -Command \"Install-Module VMware.PowerCLI -Scope CurrentUser -Force\""
    fi
}

# Cleanup
cleanup_homebrew() {
    log_info "Cleaning up Homebrew..."
    if brew cleanup; then
        log_success "Homebrew cleanup completed"
    else
        log_warning "Homebrew cleanup had issues"
    fi
}

# Main execution
main() {
    log_info "Starting GUI applications installation..."
    
    check_homebrew
    install_cask_apps
    install_powershell

    # Ask user if they want to setup PowerShell modules
    echo
    read -p "Do you want to setup PowerShell modules? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_powershell_modules
    else
        log_info "Skipping PowerShell module setup"
    fi
    
    cleanup_homebrew
    
    log_success "GUI applications installation completed!"
    log_info "Some applications may require additional setup or signing in"
}

# Run main function
main "$@"
