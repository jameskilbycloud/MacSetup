# MacSetup server helpers — sourced by every script in server/.
# Layered on top of the repo-root lib.sh (colours + log_* functions).
# Not meant to be executed directly.
#
# Targets bash 3.2 (the version macOS ships) — no associative arrays,
# no `mapfile`, no `${var,,}`.
# shellcheck shell=bash

# ──────────────────────────────────────────────
# Interaction
# ──────────────────────────────────────────────

# ask "Question?" [y|n]  → exit 0 for yes, 1 for no.
# With no TTY (CI, piped input) the default is taken without prompting, so a
# headless re-run never hangs waiting on stdin.
ask() {
    local prompt="$1"
    local default="${2:-y}"
    local reply

    if [[ ! -t 0 ]]; then
        [[ "$default" == "y" ]]
        return
    fi

    if [[ "$default" == "y" ]]; then
        read -r -p "$(echo -e "${YELLOW}?${NC} $prompt [Y/n]: ")" reply
        reply="${reply:-y}"
    else
        read -r -p "$(echo -e "${YELLOW}?${NC} $prompt [y/N]: ")" reply
        reply="${reply:-n}"
    fi

    [[ "$reply" =~ ^[Yy]$ ]]
}

# prompt_default "Label" "fallback" → echoes the answer (or the fallback).
prompt_default() {
    local label="$1"
    local fallback="${2:-}"
    local reply

    if [[ ! -t 0 ]]; then
        echo "$fallback"
        return
    fi

    read -r -p "$(echo -e "${YELLOW}?${NC} $label${fallback:+ [$fallback]}: ")" reply
    echo "${reply:-$fallback}"
}

# ──────────────────────────────────────────────
# Environment
# ──────────────────────────────────────────────

# This profile targets Apple silicon Macs only. Everything downstream assumes
# it: the Homebrew prefix is /opt/homebrew, Colima uses Virtualization.framework
# with Rosetta, and the Actions runner downloads the osx-arm64 build. Fail fast
# rather than half-installing an unsupported combination.
require_apple_silicon() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is for macOS only."
        exit 1
    fi

    # hw.optional.arm64 reports the hardware, not the process. It stays 1 even
    # when the calling shell is translated, which `uname -m` would not show.
    if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" != "1" ]]; then
        log_error "This server profile supports Apple silicon (M-series) Macs only."
        log_info "Detected: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)"
        exit 1
    fi

    # Apple silicon hardware, but an x86_64 shell — someone is running under
    # Rosetta. Homebrew would resolve to /usr/local and Colima would pick the
    # wrong VM backend, so stop here rather than produce a broken install.
    if [[ "$(uname -m)" != "arm64" ]]; then
        log_error "This shell is translated under Rosetta (uname -m = $(uname -m))."
        log_info "Re-run from a native shell:  arch -arm64 zsh"
        exit 1
    fi
}

# Ask for the admin password once and keep the sudo timestamp warm for the
# duration of the script, so long installs don't stall on a re-prompt.
require_sudo() {
    [[ -n "${CI:-}" ]] && return 0

    if ! sudo -v; then
        log_error "This step needs administrator rights."
        exit 1
    fi

    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done 2>/dev/null &
}

# Apple silicon puts Homebrew at /opt/homebrew, always — no prefix hunting.
BREW_BIN="/opt/homebrew/bin/brew"

ensure_brew_in_path() {
    command -v brew &>/dev/null && return 0
    [[ -x "$BREW_BIN" ]] && eval "$("$BREW_BIN" shellenv)"
    return 0
}

require_brew() {
    ensure_brew_in_path
    if ! command -v brew &>/dev/null; then
        log_error "Homebrew is not installed. Run server/brew-server.sh first."
        exit 1
    fi
}

# ──────────────────────────────────────────────
# Command running
# ──────────────────────────────────────────────

# try "Description" cmd args...
#
# Runs a command that is allowed to fail. A headless server setup touches a lot
# of Apple subsystems whose availability shifts between macOS releases (pmset
# keys, systemsetup verbs) — under `set -e` a single unsupported one would
# otherwise abort the whole run.
try() {
    local desc="$1"
    shift

    local output
    if output=$("$@" 2>&1); then
        log_success "$desc"
        return 0
    fi

    log_warning "$desc — skipped"
    if [[ -n "$output" ]]; then
        echo "$output" | tail -3 | sed 's/^/    /'
    fi
    return 0
}

# ──────────────────────────────────────────────
# Diagnostics
# ──────────────────────────────────────────────

# Several things a headless Mac needs — colima's brew service, the Actions
# runner LaunchAgent, Plex Media Server — run as the *user*, not as root, so
# they only start once someone is logged in. Without automatic login the box
# comes back from a reboot with none of them running.
autologin_user() {
    defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true
}

warn_if_no_autologin() {
    local user
    user="$(autologin_user)"

    if [[ -n "$user" ]]; then
        log_success "Automatic login is enabled for '$user'"
        return 0
    fi

    log_warning "Automatic login is OFF — user LaunchAgents won't start after a reboot"
    log_info "Enable it: System Settings → Users & Groups → Automatically log in as…"
    log_info "Note: FileVault blocks automatic login. See server/README.md for the trade-off."
}
