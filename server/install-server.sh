#!/usr/bin/env bash

# MacSetup (server) — headless Mac mini installer
#
# The counterpart to the repo-root install.sh. That one sets up a machine you
# sit in front of; this one sets up a machine you only ever reach over the
# network. Steps run in dependency order and each can be skipped.
#
# Run the whole thing from the physical console (or an existing Screen Sharing
# session) the first time — the SSH step can drop you if you get it wrong, and
# a couple of macOS toggles need a GUI.

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

SKIPPED=()
FAILED=()

# run_step "Name" "path/relative/to/repo/root" "What it does" [VAR=value ...]
run_step() {
    local name="$1"
    local rel_path="$2"
    local description="$3"
    shift 3

    log_header "Step: $name"
    log_info "$description"
    echo

    if ! ask "Run $name?"; then
        log_warning "Skipping $name"
        SKIPPED+=("$name")
        return 0
    fi

    local script="$REPO_ROOT/$rel_path"
    if [[ ! -f "$script" ]]; then
        log_error "Script not found: $script"
        FAILED+=("$name (missing script)")
        return 0
    fi

    # A failed step must not abort the run — the later steps are independent,
    # and on a headless box you want to reach the end and read the summary
    # rather than discover at step 3 that steps 4-10 never happened.
    local status=0
    env "$@" bash "$script" || status=$?

    if [[ "$status" -eq 0 ]]; then
        log_success "$name completed"
    else
        log_error "$name failed (exit $status)"
        FAILED+=("$name")
    fi
}

preflight() {
    log_header "Pre-flight Checks"

    require_apple_silicon
    log_success "Running on macOS $(sw_vers -productVersion)"

    log_info "Hardware: $(sysctl -n hw.model 2>/dev/null || echo unknown)"
    log_info "Chip:     $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple silicon")"
    log_info "Cores:    $(sysctl -n hw.ncpu 2>/dev/null || echo "?") · \
RAM: $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 / 1024 ))GB"

    if ! curl -s --max-time 5 https://www.apple.com &>/dev/null; then
        log_error "No internet connection detected. Connect and try again."
        exit 1
    fi
    log_success "Internet connectivity confirmed"

    if ! xcode-select -p &>/dev/null; then
        log_info "Installing Xcode Command Line Tools (required by Homebrew)..."
        xcode-select --install
        log_warning "Finish the Xcode CLT prompt, then re-run this script."
        exit 0
    fi
    log_success "Xcode Command Line Tools found"

    # Battery-powered Macs make poor always-on servers, and several power
    # settings below assume mains. Worth flagging, not worth blocking.
    if pmset -g batt 2>/dev/null | grep -q "InternalBattery"; then
        log_warning "This machine has an internal battery — the power settings assume mains power"
    fi

    echo
    warn_if_no_autologin
    echo
}

summary() {
    log_header "Installation Complete"

    if [[ ${#SKIPPED[@]} -gt 0 ]]; then
        log_warning "Skipped ${#SKIPPED[@]} step(s):"
        printf '  - %s\n' "${SKIPPED[@]}"
        echo
    fi

    if [[ ${#FAILED[@]} -gt 0 ]]; then
        log_error "Failed ${#FAILED[@]} step(s):"
        printf '  - %s\n' "${FAILED[@]}"
        echo
        log_info "Re-run an individual step directly, e.g.: bash server/power-setup.sh"
        echo
    else
        log_success "Every step that ran completed successfully"
        echo
    fi

    log_info "Finish up manually:"
    echo "  1. Enable automatic login (Users & Groups) so LaunchAgents survive a reboot"
    echo "  2. Claim Plex at http://$(scutil --get LocalHostName 2>/dev/null || hostname).local:32400/web"
    echo "  3. Test SSH from another machine BEFORE closing this session"
    echo "  4. Reboot once and confirm everything comes back on its own"
    echo
    log_info "Verify the result any time with: bash server/healthcheck.sh"
    echo
}

main() {
    echo
    echo -e "${BOLD}${CYAN}"
    echo "  ███╗   ███╗ █████╗  ██████╗    ███████╗██████╗ ██╗   ██╗"
    echo "  ████╗ ████║██╔══██╗██╔════╝    ██╔════╝██╔══██╗██║   ██║"
    echo "  ██╔████╔██║███████║██║         ███████╗██████╔╝██║   ██║"
    echo "  ██║╚██╔╝██║██╔══██║██║         ╚════██║██╔══██╗╚██╗ ██╔╝"
    echo "  ██║ ╚═╝ ██║██║  ██║╚██████╗    ███████║██║  ██║ ╚████╔╝ "
    echo "  ╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝    ╚══════╝╚═╝  ╚═╝  ╚═══╝  "
    echo -e "${NC}"
    echo -e "  ${BLUE}Headless Mac mini server setup by James Kilby${NC}"
    echo

    preflight

    run_step "Homebrew & Server Packages" \
        "server/brew-server.sh" \
        "Installs Homebrew, CLI/DevOps tooling, container tools and Plex Media Server."

    # brew.sh runs in a subshell, so its PATH changes don't reach us.
    ensure_brew_in_path

    run_step "Git Configuration" \
        "git-setup.sh" \
        "Shared with the desktop setup: global gitignore, default branch, colour output."

    run_step "Zsh & Oh-My-Zsh" \
        "zsh-setup.sh" \
        "Shared with the desktop setup, minus the Nerd Font (nothing here renders it)." \
        MACSETUP_SKIP_FONT=1

    run_step "macOS Server Defaults" \
        "server/defaults-server.sh" \
        "Hostname, no modal dialogs, no App Nap, security-updates-only policy."

    run_step "Power Management" \
        "server/power-setup.sh" \
        "Never sleep, restart after power failure or freeze, wake on network."

    run_step "SSH Access" \
        "server/ssh-setup.sh" \
        "Enables Remote Login, installs your public keys, then disables password auth."

    run_step "Screen Sharing" \
        "server/screen-sharing.sh" \
        "Enables Remote Management as an escape hatch for GUI-only macOS tasks."

    run_step "Container Runtime" \
        "server/docker-setup.sh" \
        "Colima + docker CLI (not Docker Desktop), sized to this hardware, autostarting."

    run_step "GitHub Actions Runner" \
        "server/ci-runner-setup.sh" \
        "Optional: installs and registers a self-hosted runner as a launchd service."

    run_step "Unattended Maintenance" \
        "server/maintenance-setup.sh" \
        "Weekly LaunchAgent running brew update/upgrade/cleanup/doctor with a log."

    summary
}

main "$@"
