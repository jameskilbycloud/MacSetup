#!/usr/bin/env bash

# MacSetup Homebrew Installation Script
# Installs Homebrew and essential command-line tools

set -euo pipefail  # Exit on error, undefined vars, pipe failures

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f "$SCRIPT_DIR/lib.sh" ]]; then
    echo "Error: missing $SCRIPT_DIR/lib.sh (required by this script)" >&2
    exit 1
fi
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Check if Homebrew is installed
install_homebrew() {
    if ! command -v brew &> /dev/null; then
        log_info "Homebrew not found. Installing Homebrew..."
        if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
            log_success "Homebrew installed successfully"
            
            # Add Homebrew to PATH for Apple Silicon Macs
            if [[ $(uname -m) == "arm64" ]]; then
                if ! grep -q "brew shellenv" ~/.zprofile 2>/dev/null; then
                    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
                fi
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi
        else
            log_error "Failed to install Homebrew"
            exit 1
        fi
    else
        log_info "Homebrew already installed"
    fi
}

# Update Homebrew
update_homebrew() {
    log_info "Updating Homebrew..."
    if brew update; then
        log_success "Homebrew updated successfully"
    else
        log_warning "Failed to update Homebrew, continuing..."
    fi
}

# Install formula packages
install_formulas() {
    log_info "Installing Homebrew formulas..."
    
    # Add HashiCorp tap for their tools
    log_info "Adding HashiCorp tap..."
    brew tap hashicorp/tap
    
    # Define formula packages (command-line tools)
    local formulas=(
        # DevOps & Infrastructure
        "ansible"           # Automation tool
        "awscli"            # AWS command line interface
        "govc"              # vSphere CLI
        "helm"              # Kubernetes package manager
        "kubernetes-cli"    # Kubernetes command line tool
        "kubectx"           # Switch kubectl contexts
        "k9s"               # Kubernetes TUI
        "hashicorp/tap/packer"  # Tool for building machine images
        "hashicorp/tap/terraform"  # Infrastructure as code
        "hashicorp/tap/vault"      # Secrets management
        "wireguard-tools"   # WireGuard VPN tools
        # Note: wrangler (Cloudflare Workers CLI) should be installed via npm: npm install -g wrangler
        
        # Modern CLI Tools
        "btop"              # Better system monitor
        "eza"               # Modern ls replacement
        "fd"                # Better find
        "fzf"               # Fuzzy finder
        "gh"                # GitHub CLI
        "git-delta"         # Beautiful git diffs
        "httpie"            # Better curl for APIs
        "jq"                # JSON processor
        "lazygit"           # Terminal UI for git
        "ripgrep"           # Faster grep
        "tldr"              # Simplified man pages
        "zoxide"            # Smart cd
        
        # System Utilities
        "asciinema"         # Terminal session recorder
        "htop"              # Better top
        "mackup"            # Backup and restore application settings
        "mas"               # Mac App Store command line interface
        "ncdu"              # Disk usage analyzer
        "nmap"              # Network discovery and security auditing
        "openssl"           # SSL/TLS cryptography library
        "tmux"              # Terminal multiplexer
        "watch"             # Execute commands periodically
        
        # Programming Languages
        "node"              # Node.js (includes npm)
        "ruby"              # Ruby programming language
        "zsh"               # Z shell
    )
    
    # Install formulas in batch for better performance
    if brew install "${formulas[@]}"; then
        log_success "All formulas installed successfully"
    else
        log_warning "Some formulas may have failed to install. Checking individually..."
        
        # Install individually to identify failures
        for formula in "${formulas[@]}"; do
            if brew install "$formula" 2>/dev/null; then
                log_success "Installed: $formula"
            else
                log_error "Failed to install: $formula"
            fi
        done
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
    log_info "Starting Homebrew setup..."
    
    install_homebrew
    update_homebrew
    install_formulas
    cleanup_homebrew

    log_success "Homebrew setup completed!"
    log_info "You may need to restart your terminal or run 'source ~/.zprofile' to use newly installed tools"
}

# Run main function
main "$@"
