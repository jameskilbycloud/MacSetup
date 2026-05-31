#!/usr/bin/env bash

# MacSetup Mackup Configuration Script
# Configures Mackup to sync application settings via iCloud

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f "$SCRIPT_DIR/lib.sh" ]]; then
    echo "Error: missing $SCRIPT_DIR/lib.sh (required by this script)" >&2
    exit 1
fi
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
MACKUP_CFG="$HOME/.mackup.cfg"

check_dependencies() {
    if ! command -v mackup &>/dev/null; then
        log_error "mackup is not installed. Run brew.sh first."
        exit 1
    fi
}

check_icloud() {
    if [[ ! -d "$ICLOUD_DIR" ]]; then
        log_error "iCloud Drive not found at: $ICLOUD_DIR"
        log_info "Make sure iCloud Drive is enabled in System Settings → Apple ID → iCloud."
        exit 1
    fi
    log_success "iCloud Drive found"
}

install_config() {
    if [[ -f "$MACKUP_CFG" ]]; then
        log_warning "Existing ~/.mackup.cfg found — backing up to ~/.mackup.cfg.bak"
        cp "$MACKUP_CFG" "$MACKUP_CFG.bak"
    fi

    cp "$SCRIPT_DIR/mackup.cfg" "$MACKUP_CFG"
    log_success "Installed mackup config to ~/.mackup.cfg (iCloud engine)"
}

run_mackup() {
    echo
    log_info "What would you like to do?"
    echo "  1) backup  — push your current dotfiles to iCloud"
    echo "  2) restore — pull dotfiles from iCloud to this Mac"
    echo "  3) list    — show which apps mackup will manage"
    echo "  4) skip    — do nothing (config is installed, run mackup manually)"
    echo
    read -rp "Choice [1/2/3/4]: " choice

    case "$choice" in
        1)
            log_info "Running: mackup backup"
            mackup backup
            log_success "Backup complete — settings synced to iCloud"
            ;;
        2)
            log_info "Running: mackup restore"
            log_warning "This will replace local dotfiles with those from iCloud."
            read -rp "Continue? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                mackup restore
                log_success "Restore complete — settings pulled from iCloud"
            else
                log_info "Restore cancelled"
            fi
            ;;
        3)
            mackup list
            ;;
        4)
            log_info "Skipping — run 'mackup backup' or 'mackup restore' when ready"
            ;;
        *)
            log_warning "Invalid choice — skipping"
            ;;
    esac
}

main() {
    log_info "Configuring Mackup..."
    echo
    log_info "Mackup symlinks your app dotfiles into iCloud so they're automatically"
    log_info "available on every Mac you own. Settings are stored at:"
    log_info "  ~/Library/Mobile Documents/com~apple~CloudDocs/Mackup/"
    echo

    check_dependencies
    check_icloud
    install_config
    run_mackup

    echo
    log_info "Mackup cheatsheet:"
    echo "  mackup backup   — sync current settings to iCloud"
    echo "  mackup restore  — apply iCloud settings to this Mac"
    echo "  mackup uninstall — restore original dotfiles (safe to run before removing mackup)"
    echo "  mackup list     — show all supported apps"
}

main "$@"
