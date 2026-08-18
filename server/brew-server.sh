#!/usr/bin/env bash

# MacSetup (server) — Homebrew + package installation for a headless Mac mini
#
# Differs from the desktop brew.sh in three ways:
#   • No GUI-only tooling (mackup/iCloud, mas/App Store, asciinema)
#   • Adds container, backup and remote-ops tooling
#   • Installs the one cask a media server actually needs (Plex)

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

for dep in "$REPO_ROOT/lib.sh" "$SCRIPT_DIR/lib-server.sh"; do
    if [[ ! -f "$dep" ]]; then
        echo "Error: missing $dep (required by this script)" >&2
        exit 1
    fi
done
# shellcheck source=../lib.sh
source "$REPO_ROOT/lib.sh"
# shellcheck source=lib-server.sh
source "$SCRIPT_DIR/lib-server.sh"

install_homebrew() {
    if command -v brew &>/dev/null; then
        log_info "Homebrew already installed"
        return 0
    fi

    log_info "Homebrew not found. Installing Homebrew..."
    if ! NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        log_error "Failed to install Homebrew"
        exit 1
    fi
    log_success "Homebrew installed successfully"

    # Put brew on PATH for login shells.
    ensure_brew_in_path
    if ! grep -qF "brew shellenv" "$HOME/.zprofile" 2>/dev/null; then
        printf '\neval "$(%s shellenv)"\n' "$BREW_BIN" >> "$HOME/.zprofile"
        log_success "Added brew shellenv to ~/.zprofile"
    fi
}

update_homebrew() {
    log_info "Updating Homebrew..."
    if brew update; then
        log_success "Homebrew updated"
    else
        log_warning "brew update failed — continuing with what's cached"
    fi
}

install_formulas() {
    log_info "Adding HashiCorp tap..."
    brew tap hashicorp/tap

    local formulas=(
        # DevOps & Infrastructure
        "ansible"           # Automation tool
        "awscli"            # AWS command line interface
        "govc"              # vSphere CLI
        "helm"              # Kubernetes package manager
        "kubernetes-cli"    # Kubernetes command line tool
        "kubectx"           # Switch kubectl contexts
        "k9s"               # Kubernetes TUI
        "hashicorp/tap/packer"     # Machine image builder
        "hashicorp/tap/terraform"  # Infrastructure as code
        "hashicorp/tap/vault"      # Secrets management
        "wireguard-tools"   # WireGuard VPN tools

        # Containers — colima replaces Docker Desktop, which needs a GUI session
        "colima"            # Container runtime on a Lima VM
        "docker"            # Docker CLI (no Desktop)
        "docker-compose"    # Compose v2 CLI plugin
        "docker-buildx"     # BuildKit builder plugin
        "lazydocker"        # Terminal UI for containers

        # Remote ops — a headless box is only ever reached over the network
        "mosh"              # Roaming SSH that survives dropped links
        "tmux"              # Terminal multiplexer (keep long jobs alive)
        "iperf3"            # Network throughput testing
        "mtr"               # Traceroute + ping combined
        "rsync"             # Modern rsync (macOS ships 2.6.9 from 2006)

        # Backup
        "restic"            # Encrypted, deduplicating backups
        "rclone"            # Sync to/from cloud object storage

        # Modern CLI Tools
        "bat"               # cat with syntax highlighting
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
        "htop"              # Better top
        "ncdu"              # Disk usage analyzer
        "nmap"              # Network discovery and security auditing
        "openssl"           # SSL/TLS cryptography library
        "watch"             # Execute commands periodically
        "wget"              # Non-interactive downloader

        # Programming Languages
        "node"              # Node.js (includes npm)
        "zsh"               # Z shell
    )

    log_info "Installing ${#formulas[@]} formulas..."

    if brew install "${formulas[@]}"; then
        log_success "All formulas installed successfully"
        return 0
    fi

    log_warning "Batch install reported failures — retrying individually..."
    local failed=()
    local formula
    for formula in "${formulas[@]}"; do
        if brew install "$formula" &>/dev/null; then
            log_success "Installed: $formula"
        else
            log_error "Failed to install: $formula"
            failed+=("$formula")
        fi
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        log_warning "${#failed[@]} formula(s) failed:"
        printf '  - %s\n' "${failed[@]}"
    fi
}

install_casks() {
    # A headless server gets almost no GUI software. Plex Media Server is the
    # exception: it has no CLI installer and runs as a login item, which is why
    # automatic login matters (see warn_if_no_autologin).
    local casks=(
        "plex-media-server"  # Plex Media Server
    )

    log_info "Installing ${#casks[@]} cask(s)..."

    local cask
    for cask in "${casks[@]}"; do
        if brew list --cask "$cask" &>/dev/null; then
            log_info "Already installed: $cask"
            continue
        fi
        if brew install --cask "$cask"; then
            log_success "Installed: $cask"
        else
            log_error "Failed to install: $cask — install it manually with 'brew install --cask $cask'"
        fi
    done
}

link_docker_plugins() {
    # Homebrew installs compose/buildx as standalone binaries. The docker CLI
    # only finds them as plugins (`docker compose`) if they're linked into
    # ~/.docker/cli-plugins.
    local plugin_dir="$HOME/.docker/cli-plugins"
    mkdir -p "$plugin_dir"

    local prefix
    prefix="$(brew --prefix)"

    local plugin
    for plugin in docker-compose docker-buildx; do
        local src="$prefix/opt/$plugin/bin/$plugin"
        if [[ -x "$src" ]]; then
            ln -sfn "$src" "$plugin_dir/$plugin"
            log_success "Linked $plugin into ~/.docker/cli-plugins"
        else
            log_warning "$plugin not found at $src — skipping link"
        fi
    done
}

cleanup_homebrew() {
    log_info "Cleaning up Homebrew..."
    brew cleanup || log_warning "Homebrew cleanup had issues"
}

main() {
    require_apple_silicon
    log_header "Homebrew & Server Packages"

    install_homebrew
    update_homebrew
    install_formulas
    install_casks
    link_docker_plugins
    cleanup_homebrew

    log_success "Package installation complete"
    log_info "Open a new shell (or run 'source ~/.zprofile') to pick up the new PATH"
}

main "$@"
