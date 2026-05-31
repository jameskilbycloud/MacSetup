#!/usr/bin/env bash

# MacSetup - Master Installation Script
# Orchestrates all setup scripts in the correct order

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f "$SCRIPT_DIR/lib.sh" ]]; then
    echo "Error: missing $SCRIPT_DIR/lib.sh (required by this script)" >&2
    exit 1
fi
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Ask the user a yes/no question, defaulting to Yes
ask() {
    local prompt="$1"
    local default="${2:-y}"
    local reply

    if [[ "$default" == "y" ]]; then
        read -r -p "$(echo -e "${YELLOW}?${NC} $prompt [Y/n]: ")" reply
        reply="${reply:-y}"
    else
        read -r -p "$(echo -e "${YELLOW}?${NC} $prompt [y/N]: ")" reply
        reply="${reply:-n}"
    fi

    [[ "$reply" =~ ^[Yy]$ ]]
}

# Run a script with a header and skip option
run_step() {
    local name="$1"
    local script="$2"
    local description="$3"

    log_header "Step: $name"
    log_info "$description"
    echo

    if ! ask "Run $name?"; then
        log_warning "Skipping $name"
        return 0
    fi

    if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
        log_error "Script not found: $SCRIPT_DIR/$script"
        return 1
    fi

    chmod +x "$SCRIPT_DIR/$script"
    bash "$SCRIPT_DIR/$script"
    log_success "$name completed"
}

# Make sure `brew` is on PATH for the rest of this script.
# brew.sh runs in a subshell, so its PATH changes don't propagate back here —
# without this, later steps (brew-apps.sh, mackup-setup.sh, mas-apps.sh) fail
# with "Homebrew is not installed" on a fresh machine.
ensure_brew_in_path() {
    if command -v brew &>/dev/null; then
        return 0
    fi
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

# ──────────────────────────────────────────────
# Pre-flight checks
# ──────────────────────────────────────────────
preflight() {
    log_header "MacSetup — Pre-flight Checks"

    # macOS only
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is designed for macOS only."
        exit 1
    fi

    log_success "Running on macOS $(sw_vers -productVersion)"

    # Check for internet connectivity
    if ! curl -s --max-time 5 https://www.apple.com &>/dev/null; then
        log_error "No internet connection detected. Please connect and try again."
        exit 1
    fi
    log_success "Internet connectivity confirmed"

    # Ensure Xcode Command Line Tools are installed (required by Homebrew)
    if ! xcode-select -p &>/dev/null; then
        log_info "Installing Xcode Command Line Tools (required for Homebrew)..."
        xcode-select --install
        log_warning "Please complete the Xcode CLT installation prompt, then re-run this script."
        exit 0
    fi
    log_success "Xcode Command Line Tools found"

    echo
    log_info "All pre-flight checks passed. Starting installation..."
    echo
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
main() {
    echo
    echo -e "${BOLD}${CYAN}"
    echo "  ███╗   ███╗ █████╗  ██████╗███████╗███████╗████████╗██╗   ██╗██████╗ "
    echo "  ████╗ ████║██╔══██╗██╔════╝██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗"
    echo "  ██╔████╔██║███████║██║     ███████╗█████╗     ██║   ██║   ██║██████╔╝"
    echo "  ██║╚██╔╝██║██╔══██║██║     ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ "
    echo "  ██║ ╚═╝ ██║██║  ██║╚██████╗███████║███████╗   ██║   ╚██████╔╝██║     "
    echo "  ╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     "
    echo -e "${NC}"
    echo -e "  ${BLUE}A fresh Mac setup by James Kilby${NC}"
    echo

    preflight

    run_step "Homebrew & CLI Tools" \
        "brew.sh" \
        "Installs Homebrew and CLI tools (kubectl, terraform, ansible, gh, etc.)."

    ensure_brew_in_path

    run_step "GUI Applications" \
        "brew-apps.sh" \
        "Installs GUI apps via Homebrew Cask (Chrome, VS Code, iTerm2, Docker, etc.)."

    run_step "Git Configuration" \
        "git-setup.sh" \
        "Configures global gitignore, default branch, and colour output."

    run_step "Zsh & Oh-My-Zsh" \
        "zsh-setup.sh" \
        "Installs Oh-My-Zsh, Powerlevel10k theme, plugins, and custom aliases."

    run_step "macOS System Defaults" \
        "defaults.sh" \
        "Applies Finder, Dock, keyboard, screenshot, and performance tweaks."

    run_step "Mackup (iCloud dotfile sync)" \
        "mackup-setup.sh" \
        "Syncs app settings and dotfiles via iCloud using Mackup."

    run_step "Mac App Store Apps" \
        "mas-apps.sh" \
        "Installs App Store apps (iHosts, etc.) — requires Apple ID sign-in."

    log_header "Installation Complete 🎉"
    log_success "Your Mac is set up and ready to go!"
    echo
    log_info "Recommended next steps:"
    echo "  1. Restart your terminal (or open a new tab)"
    echo "  2. Run 'p10k configure' to set up your Powerlevel10k prompt"
    echo "  3. Set your terminal font to 'Hack Nerd Font'"
    echo "  4. Log out and back in to apply all macOS defaults"
    echo
    log_info "For ongoing maintenance, run: ./brew-maintenance.sh full"
    echo
}

main "$@"
