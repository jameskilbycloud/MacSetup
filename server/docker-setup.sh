#!/usr/bin/env bash

# MacSetup (server) — container runtime via Colima
#
# Docker Desktop is the wrong tool here: it is a GUI app that will not start
# without a logged-in Aqua session, it nags about updates, and its licence
# terms are awkward for anything that looks like infrastructure. Colima runs
# the same containers in a Lima VM, starts from the CLI, and is managed by
# launchd through `brew services`.

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

# Set by ensure_rosetta() before start_colima() reads it.
ROSETTA_AVAILABLE="no"

# Size the VM from the hardware rather than guessing: half the cores and half
# the RAM leaves the host comfortable while giving containers real capacity.
suggest_cpus() {
    local cores
    cores="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    local half=$(( cores / 2 ))
    [[ "$half" -lt 2 ]] && half=2
    echo "$half"
}

suggest_memory_gb() {
    local bytes gb half
    bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    gb=$(( bytes / 1024 / 1024 / 1024 ))
    half=$(( gb / 2 ))
    [[ "$half" -lt 2 ]] && half=2
    echo "$half"
}

check_prereqs() {
    require_brew

    if ! command -v colima &>/dev/null; then
        log_error "colima is not installed. Run server/brew-server.sh first."
        exit 1
    fi

    if ! command -v docker &>/dev/null; then
        log_error "The docker CLI is not installed. Run server/brew-server.sh first."
        exit 1
    fi

    log_success "colima and docker CLI found"
}

# Colima is started with --vz-rosetta below, which needs Rosetta present on the
# host. A fresh Apple silicon Mac has never installed it, and colima fails at
# start rather than degrading, so install it up front.
ensure_rosetta() {
    if arch -x86_64 /usr/bin/true &>/dev/null; then
        log_success "Rosetta is installed"
        return 0
    fi

    log_info "Rosetta is not installed — it lets the container VM run x86_64 images."

    if ! ask "Install Rosetta now?" y; then
        log_warning "Skipping Rosetta — Colima will start without x86_64 emulation"
        return 1
    fi

    if softwareupdate --install-rosetta --agree-to-license; then
        log_success "Rosetta installed"
        return 0
    fi

    log_warning "Rosetta installation failed — continuing without x86_64 emulation"
    return 1
}

start_colima() {
    if colima status &>/dev/null; then
        log_info "Colima is already running:"
        colima status 2>&1 | sed 's/^/    /'
        if ! ask "Recreate the VM with new sizing?" n; then
            return 0
        fi
        log_info "Stopping and deleting the existing VM..."
        colima stop || true
        colima delete --force || true
    fi

    local cpus mem disk
    cpus="$(prompt_default "CPUs for the container VM" "$(suggest_cpus)")"
    mem="$(prompt_default "Memory (GB)" "$(suggest_memory_gb)")"
    disk="$(prompt_default "Disk (GB)" "100")"

    # Apple's Virtualization.framework is faster and lighter than QEMU, and
    # virtiofs is much faster than sshfs for bind mounts.
    local args=(start --cpu "$cpus" --memory "$mem" --disk "$disk"
                --vm-type=vz --mount-type=virtiofs)

    # Rosetta inside the VM runs x86_64 images that have no arm64 build. Only
    # request it if the host actually has Rosetta — otherwise colima errors out.
    if [[ "$ROSETTA_AVAILABLE" == "yes" ]]; then
        args+=(--vz-rosetta)
        log_info "Using Virtualization.framework + Rosetta (x86_64 images supported)"
    else
        log_warning "Using Virtualization.framework without Rosetta — arm64 images only"
    fi

    log_info "Starting Colima (${cpus} CPU, ${mem}GB RAM, ${disk}GB disk)..."
    if colima "${args[@]}"; then
        log_success "Colima started"
    else
        log_error "Colima failed to start"
        log_info "Inspect the log: colima start --verbose"
        return 1
    fi
}

enable_autostart() {
    log_info "Registering Colima to start automatically..."

    if brew services start colima; then
        log_success "Colima registered with brew services"
    else
        log_warning "Could not register Colima with brew services"
        return 0
    fi

    echo
    log_warning "brew services installs a LaunchAgent, which only runs inside a"
    log_warning "logged-in user session. Without automatic login, containers will"
    log_warning "not come back after a reboot."
    warn_if_no_autologin
}

verify() {
    log_info "Verifying the container runtime..."

    if ! docker context ls &>/dev/null; then
        log_warning "docker CLI cannot reach any context yet"
        return 0
    fi

    try "Select the colima docker context" docker context use colima

    if docker run --rm hello-world &>/dev/null; then
        log_success "Container runtime verified (ran hello-world)"
    else
        log_warning "Could not run a test container — check 'colima status' and 'docker info'"
    fi

    if docker compose version &>/dev/null; then
        log_success "docker compose plugin available"
    else
        log_warning "docker compose plugin not found — re-run server/brew-server.sh to link it"
    fi
}

main() {
    require_apple_silicon
    log_header "Container Runtime — Colima"

    check_prereqs

    if ensure_rosetta; then
        ROSETTA_AVAILABLE=yes
    else
        ROSETTA_AVAILABLE=no
    fi

    start_colima || exit 1
    enable_autostart
    verify

    echo
    log_success "Container setup complete"
    log_info "Useful commands:"
    echo "    colima status              — VM state and resources"
    echo "    colima stop / colima start — control the VM"
    echo "    lazydocker                 — terminal UI for containers"
    echo "    brew services list         — confirm colima is registered"
}

main "$@"
