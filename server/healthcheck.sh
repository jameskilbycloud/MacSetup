#!/usr/bin/env bash

# MacSetup (server) — is this box actually healthy?
#
# Read-only. Run it over SSH after a reboot, or any time something feels off.
# Exits non-zero if any check fails, so it also works from a monitoring job.

set -uo pipefail   # deliberately NOT -e: every check must run, then report

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

PASS=0
WARN=0
FAIL=0

pass() { log_success "$1"; PASS=$(( PASS + 1 )); }
warn() { log_warning "$1"; WARN=$(( WARN + 1 )); }
fail() { log_error   "$1"; FAIL=$(( FAIL + 1 )); }

check_uptime() {
    log_header "Host"
    log_info "$(scutil --get ComputerName 2>/dev/null || hostname) — macOS $(sw_vers -productVersion) on $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple silicon")"
    log_info "Uptime:$(uptime | sed 's/.*up //; s/,.*load/ — load/')"

    local free_pct
    free_pct="$(df -h / | awk 'NR==2 {gsub("%","",$5); print 100-$5}')"
    if [[ -n "$free_pct" && "$free_pct" -lt 10 ]]; then
        fail "Boot volume is ${free_pct}% free"
    else
        pass "Boot volume ${free_pct:-?}% free"
    fi
}

check_power() {
    log_header "Power"

    local custom
    custom="$(pmset -g custom 2>/dev/null)"

    if echo "$custom" | grep -qE '^\s*sleep\s+0'; then
        pass "System sleep is disabled"
    else
        fail "System sleep is NOT disabled — this box can nap through requests"
    fi

    if echo "$custom" | grep -qE '^\s*autorestart\s+1'; then
        pass "Restarts automatically after a power failure"
    else
        warn "autorestart is off — a power cut leaves this machine down"
    fi

    if pmset -g assertions 2>/dev/null | grep -qE 'PreventUserIdleSystemSleep.*1'; then
        log_info "Something is holding a wake assertion (normal while jobs run)"
    fi
}

check_ssh() {
    log_header "SSH"

    if sudo -n systemsetup -getremotelogin 2>/dev/null | grep -qi "on$"; then
        pass "Remote Login is enabled"
    elif nc -z -G 2 localhost 22 &>/dev/null; then
        pass "sshd is listening on port 22"
    else
        fail "sshd does not appear to be listening"
    fi

    local keys=0
    if [[ -f "$HOME/.ssh/authorized_keys" ]]; then
        keys="$(grep -cE '^(ssh-|ecdsa-sha2-|sk-)' "$HOME/.ssh/authorized_keys" 2>/dev/null)" || keys=0
    fi

    if [[ "${keys:-0}" -gt 0 ]]; then
        pass "$keys authorised SSH key(s) installed"
    else
        fail "No authorised SSH keys — you are relying on password login"
    fi

    if [[ -f /etc/ssh/sshd_config.d/100-macsetup-server.conf ]]; then
        pass "SSH hardening drop-in is in place"
    else
        warn "No SSH hardening drop-in — password authentication may be enabled"
    fi
}

check_autologin() {
    log_header "Login Session"

    local user
    user="$(autologin_user)"
    if [[ -n "$user" ]]; then
        pass "Automatic login enabled for '$user'"
    else
        warn "Automatic login is off — user LaunchAgents won't start after a reboot"
    fi

    if fdesetup status 2>/dev/null | grep -q "FileVault is On"; then
        warn "FileVault is on — reboot with 'sudo fdesetup authrestart' or the box stays locked"
    else
        pass "FileVault is off — unattended reboots come back cleanly"
    fi
}

check_containers() {
    log_header "Containers"

    if ! command -v colima &>/dev/null; then
        log_info "colima not installed — skipping"
        return
    fi

    if colima status &>/dev/null; then
        pass "Colima VM is running"
    else
        fail "Colima is not running — 'colima start' to bring containers back"
        return
    fi

    if docker info &>/dev/null; then
        pass "docker CLI can reach the daemon"
        local running
        running="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
        log_info "Running containers: ${running:-0}"
    else
        fail "docker CLI cannot reach the daemon"
    fi
}

check_plex() {
    log_header "Plex"

    if [[ ! -d "/Applications/Plex Media Server.app" ]]; then
        log_info "Plex Media Server not installed — skipping"
        return
    fi

    if pgrep -q -f "Plex Media Server"; then
        pass "Plex Media Server process is running"
    else
        fail "Plex Media Server is installed but not running"
        return
    fi

    if curl -fsS --max-time 5 -o /dev/null "http://127.0.0.1:32400/identity"; then
        pass "Plex is responding on port 32400"
    else
        warn "Plex is running but not answering on 32400 yet"
    fi
}

check_ci_runner() {
    log_header "CI Runner"

    if [[ ! -f "$HOME/actions-runner/.runner" ]]; then
        log_info "No Actions runner configured — skipping"
        return
    fi

    if pgrep -q -f "Runner.Listener"; then
        pass "Actions runner is listening for jobs"
    else
        fail "Actions runner is configured but not running — 'cd ~/actions-runner && ./svc.sh start'"
    fi
}

check_maintenance() {
    log_header "Maintenance"

    local label="cloud.jameskilby.macsetup.maintenance"
    if launchctl list 2>/dev/null | grep -q "$label"; then
        pass "Weekly maintenance agent is loaded"
    else
        warn "Maintenance agent not loaded — run server/maintenance-setup.sh"
    fi

    local outdated
    outdated="$(brew outdated --quiet 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "${outdated:-0}" -gt 20 ]]; then
        warn "$outdated outdated Homebrew packages — maintenance may not be running"
    else
        pass "${outdated:-0} outdated Homebrew package(s)"
    fi
}

main() {
    require_apple_silicon

    # `ssh host ./healthcheck.sh` runs a non-interactive shell, which never
    # sources .zprofile — so brew, colima and docker would all appear missing.
    ensure_brew_in_path

    check_uptime
    check_power
    check_ssh
    check_autologin
    check_containers
    check_plex
    check_ci_runner
    check_maintenance

    log_header "Summary"
    echo -e "  ${GREEN}pass: $PASS${NC}   ${YELLOW}warn: $WARN${NC}   ${RED}fail: $FAIL${NC}"
    echo

    [[ "$FAIL" -eq 0 ]]
}

main "$@"
