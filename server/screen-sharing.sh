#!/usr/bin/env bash

# MacSetup (server) — Screen Sharing / Remote Management
#
# SSH covers day-to-day work, but a few things on macOS simply have no
# headless path: signing in to the App Store, claiming a Plex server,
# granting an app Full Disk Access, or clearing a modal that appeared anyway.
# This enables macOS Screen Sharing for those cases.
#
# Access is restricted to specific users and authenticated with their macOS
# account. The legacy "VNC password" is deliberately left off — it is a weak,
# separately-stored shared secret.

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

KICKSTART="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"

enable_remote_management() {
    if [[ ! -x "$KICKSTART" ]]; then
        log_error "kickstart not found at $KICKSTART"
        log_info "Enable manually: System Settings → General → Sharing → Screen Sharing"
        return 1
    fi

    local user
    user="$(prompt_default "Grant Screen Sharing access to which user?" "$(whoami)")"

    if ! id "$user" &>/dev/null; then
        log_error "No such user: $user"
        return 1
    fi

    log_info "Enabling Remote Management for '$user'..."

    # -specifiedUsers restricts access to the list configured below, rather
    # than every account on the machine.
    if sudo "$KICKSTART" -activate -configure -access -on \
        -restart -agent -privs -all \
        -allowAccessFor -specifiedUsers 2>&1 | sed 's/^/    /'; then
        log_success "Remote Management activated"
    else
        log_error "kickstart failed — see output above"
        return 1
    fi

    if sudo "$KICKSTART" -configure -users "$user" -access -on -privs -all 2>&1 | sed 's/^/    /'; then
        log_success "Granted full Screen Sharing privileges to '$user'"
    else
        log_error "Could not grant privileges to '$user'"
        return 1
    fi
}

enable_screen_sharing_service() {
    log_info "Enabling the Screen Sharing service..."
    try "Enable com.apple.screensharing" \
        sudo launchctl enable system/com.apple.screensharing
    try "Load com.apple.screensharing" \
        sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist
}

report_access() {
    local host
    host="$(scutil --get LocalHostName 2>/dev/null || hostname)"

    echo
    log_success "Screen Sharing is available at:"
    echo "    vnc://${host}.local"
    echo "    (or: open -a 'Screen Sharing' vnc://${host}.local)"
    echo
    log_info "Authenticate with the macOS account password — there is no separate VNC password."
    log_warning "Do not port-forward 5900 to the internet. Reach it over your LAN or a VPN."
}

main() {
    require_apple_silicon
    log_header "Screen Sharing / Remote Management"

    log_info "Screen Sharing exists here as an escape hatch for the handful of"
    log_info "macOS tasks that cannot be done over SSH. It is not the main path in."
    echo

    if ! ask "Enable Screen Sharing?" y; then
        log_info "Skipping Screen Sharing"
        exit 0
    fi

    require_sudo

    # Modern macOS gates these calls behind Full Disk Access for the calling
    # terminal, exactly as it does for Remote Login.
    if ! enable_remote_management; then
        echo
        log_warning "Could not configure Remote Management from the command line."
        log_info "macOS may require Full Disk Access for your terminal. Either:"
        log_info "  a) System Settings → General → Sharing → turn on 'Screen Sharing', or"
        log_info "  b) grant Full Disk Access to your terminal and re-run this script"
        exit 0
    fi

    enable_screen_sharing_service
    report_access
}

main "$@"
