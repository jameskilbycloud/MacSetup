#!/usr/bin/env bash

# MacSetup (server) — power management for an always-on Apple silicon Mac mini
#
# The single most important script in server/. A stock Mac mini sleeps, and a
# sleeping server is an outage. It also needs to come back on its own after a
# power cut or a kernel panic, because nobody is there to press the button.
#
# Every setting goes through `try`: the set of supported pmset keys still shifts
# between macOS releases, and one rejected key shouldn't abort the run.

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

# Never sleep the machine or its disks. The display is allowed to sleep — it
# costs nothing to blank an output nobody is watching, and it does not suspend
# anything running.
configure_sleep() {
    log_info "Disabling system sleep..."

    try "System sleep: never"        sudo pmset -a sleep 0
    try "Disk sleep: never"          sudo pmset -a disksleep 0
    try "Display sleep: 10 minutes"  sudo pmset -a displaysleep 10

    # Keep the machine awake while a TTY session is open, so a long-running
    # SSH job is never cut short by a sleep transition.
    try "Stay awake for TTY sessions" sudo pmset -a ttyskeepawake 1

    # Not setting standby / autopoweroff / hibernatemode. Those tune the Intel
    # suspend-to-disk path; Apple silicon manages low-power states itself and
    # the keys are inert here — with `sleep 0` set, there is nothing to tune.
}

# Come back without human intervention.
configure_recovery() {
    log_info "Configuring unattended recovery..."

    # Restart automatically after a power failure. This is the one that saves
    # you after a UPS runs out or a breaker trips.
    try "Restart after power failure" sudo pmset -a autorestart 1

    # Restart automatically after a kernel panic / freeze.
    try "Restart after a freeze" sudo systemsetup -setrestartfreeze on

    # Redundant with pmset sleep 0, but systemsetup is what the Sharing pane
    # reads, so setting both keeps the GUI consistent with reality.
    try "Computer sleep: never" sudo systemsetup -setcomputersleep Never
}

# Let the machine be woken over the network.
configure_wake() {
    log_info "Configuring wake-on-network..."

    # Wake for network access. Harmless when the box never sleeps, and it means
    # a Wake-on-LAN packet still works if you later re-enable sleep.
    try "Wake on network access" sudo pmset -a womp 1

    # Power Nap wakes the machine periodically for background maintenance. On a
    # machine that is already awake it just adds dark-wake churn.
    try "Disable Power Nap" sudo pmset -a powernap 0
}

warn_about_filevault() {
    local status
    status="$(fdesetup status 2>/dev/null || echo "unknown")"

    if [[ "$status" != *"FileVault is On"* ]]; then
        log_info "FileVault is off — unattended reboots will come back cleanly"
        return 0
    fi

    echo
    log_warning "FileVault is ON."
    log_info "A FileVault-encrypted Mac stops at the login screen after a reboot and"
    log_info "will not start any user LaunchAgent (colima, Plex, the Actions runner)"
    log_info "until someone unlocks it — which defeats 'autorestart 1'."
    echo
    log_info "Reboot remotely with:  sudo fdesetup authrestart"
    log_info "  (that one command unlocks the volume for the next boot only)"
    log_info "Or turn FileVault off if this box lives somewhere physically secure."
}

show_summary() {
    log_header "Current Power Settings"
    pmset -g custom || true
    echo
    log_info "Wake/sleep history:  pmset -g log | grep -E 'Sleep|Wake'"
    log_info "Assertions holding the machine awake:  pmset -g assertions"
}

main() {
    require_apple_silicon
    log_header "Power Management — Always-On Server"
    require_sudo

    configure_sleep
    configure_recovery
    configure_wake
    warn_about_filevault
    show_summary

    echo
    log_success "Power settings applied"
}

main "$@"
