#!/usr/bin/env bash

# MacSetup (server) — macOS defaults for a headless Mac mini
#
# The desktop defaults.sh optimises for someone sitting in front of the machine
# (Dock behaviour, screenshots, Finder chrome). This one optimises for a box
# nobody is looking at: nothing modal, nothing that idles or sleeps, nothing
# that quietly throttles a background process.

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

###############################################################################
# Identity
###############################################################################

set_hostname() {
    local current
    current="$(scutil --get ComputerName 2>/dev/null || echo "")"

    log_info "Current computer name: ${current:-<unset>}"

    if ! ask "Set a new hostname for this server?" n; then
        log_info "Leaving hostname as '$current'"
        return 0
    fi

    local name
    name="$(prompt_default "Hostname (letters, digits, hyphens)" "$current")"

    if [[ -z "$name" ]]; then
        log_warning "Empty hostname — skipping"
        return 0
    fi

    if [[ ! "$name" =~ ^[A-Za-z0-9-]+$ ]]; then
        log_error "'$name' contains characters that are invalid in a hostname — skipping"
        return 0
    fi

    try "Set ComputerName to '$name'"  sudo scutil --set ComputerName "$name"
    try "Set HostName to '$name'"      sudo scutil --set HostName "$name"
    try "Set LocalHostName to '$name'" sudo scutil --set LocalHostName "$name"
    try "Set NetBIOS name"             sudo defaults write \
        /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$name"
}

###############################################################################
# Nothing modal — no dialog should ever be able to block an unattended machine
###############################################################################

quiet_the_ui() {
    log_info "Suppressing dialogs and notifications..."

    # A crash reporter dialog on a headless box is a process that never exits.
    defaults write com.apple.CrashReporter DialogType -string "none"

    # Don't offer to use every newly-attached disk as a Time Machine target.
    sudo defaults write /Library/Preferences/com.apple.TimeMachine \
        DoNotOfferNewDisksForBackup -bool true

    # Don't re-open every app's windows after a reboot.
    defaults write com.apple.loginwindow TALLogoutSavesState -bool false

    # Deliberately NOT disabling Gatekeeper quarantine (LSQuarantine). It is
    # tempting on an unattended box, but it only ever prompts inside a GUI
    # session and turning it off removes a real defence for no real gain here.

    # Disable Notification Center banners for the auto-login session.
    defaults write com.apple.notificationcenterui bannerTime -int 1

    log_success "Dialogs and notifications quietened"
}

###############################################################################
# Don't idle, don't throttle
###############################################################################

stay_responsive() {
    log_info "Disabling idle behaviour and background throttling..."

    # App Nap throttles apps macOS believes are idle. On a server, "idle" is
    # usually "waiting on the network" — exactly what shouldn't be slowed down.
    defaults write NSGlobalDomain NSAppSleepDisabled -bool true

    # macOS will terminate "inactive" apps to reclaim memory. Not helpful when
    # the inactive app is Plex waiting for a client.
    defaults write NSGlobalDomain NSDisableAutomaticTermination -bool true

    # Never start the screen saver — it does nothing useful here and gets in the
    # way of a Screen Sharing session.
    defaults -currentHost write com.apple.screensaver idleTime -int 0

    log_success "Idle behaviour disabled"
}

###############################################################################
# Software updates — take security fixes, don't take surprise OS upgrades
###############################################################################

configure_updates() {
    log_info "Configuring software update policy..."

    local su=/Library/Preferences/com.apple.SoftwareUpdate

    try "Enable update checks"            sudo defaults write "$su" AutomaticCheckEnabled -bool true
    try "Enable background downloads"     sudo defaults write "$su" AutomaticDownload -bool true
    try "Auto-install security responses" sudo defaults write "$su" \
        CriticalUpdateInstall -bool true
    try "Auto-install system data files"  sudo defaults write "$su" \
        ConfigDataInstall -bool true

    # An unattended macOS major upgrade reboots the box and can break colima,
    # the Actions runner and Plex all at once. Schedule those yourself.
    try "Disable automatic macOS upgrades" sudo defaults write "$su" \
        AutomaticallyInstallMacOSUpdates -bool false

    log_info "Security updates install automatically; macOS upgrades stay manual"
}

###############################################################################
# Filesystem and shell ergonomics (useful over SSH and Screen Sharing)
###############################################################################

configure_filesystem() {
    log_info "Applying filesystem defaults..."

    defaults write NSGlobalDomain AppleShowAllExtensions -bool true
    defaults write com.apple.finder AppleShowAllFiles -bool true
    defaults write com.apple.finder ShowPathbar -bool true
    defaults write com.apple.finder ShowStatusBar -bool true
    defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
    defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

    # Keep .DS_Store off network shares — matters more here, since this box is
    # likely the thing serving those shares.
    defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
    defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

    # Faster key repeat, no autocorrect — for the occasional Screen Sharing session.
    defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
    defaults write NSGlobalDomain KeyRepeat -int 2
    defaults write NSGlobalDomain InitialKeyRepeat -int 15
    defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

    log_success "Filesystem and input defaults applied"
}

###############################################################################
# Spotlight (optional)
###############################################################################

configure_spotlight() {
    echo
    log_info "Spotlight indexes every file it can see. On a media or CI server"
    log_info "that means continuous mdworker churn over data you never search."
    log_warning "Disabling it also breaks Spotlight search in the GUI session."

    if ! ask "Disable Spotlight indexing on the boot volume?" n; then
        log_info "Leaving Spotlight indexing enabled"
        return 0
    fi

    try "Disable Spotlight indexing on /" sudo mdutil -i off -d /
    log_info "Re-enable later with: sudo mdutil -i on /"
}

###############################################################################
# Apply
###############################################################################

restart_affected() {
    log_info "Restarting affected services..."
    # killall exits non-zero when nothing matches, which would abort under set -e.
    killall Finder &>/dev/null || true
    killall Dock &>/dev/null || true
    killall SystemUIServer &>/dev/null || true
    killall NotificationCenter &>/dev/null || true
}

main() {
    require_apple_silicon
    log_header "macOS Defaults — Headless Server"
    require_sudo

    # Close System Settings so it can't overwrite what we're about to change.
    osascript -e 'tell application "System Settings" to quit' &>/dev/null || true
    osascript -e 'tell application "System Preferences" to quit' &>/dev/null || true

    set_hostname
    quiet_the_ui
    stay_responsive
    configure_updates
    configure_filesystem
    configure_spotlight
    restart_affected

    echo
    log_success "Server defaults applied"
    log_info "Some changes take effect after the next login or reboot."
}

main "$@"
