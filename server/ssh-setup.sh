#!/usr/bin/env bash

# MacSetup (server) — SSH access, key-only
#
# Order matters here and the script enforces it: keys are installed and
# verified BEFORE password authentication is switched off. Getting that
# backwards on a machine with no keyboard attached means a trip to wherever
# the mini lives with a monitor under your arm.

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

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
SSHD_DROPIN="$SSHD_DROPIN_DIR/100-macsetup-server.conf"
AUTH_KEYS="$HOME/.ssh/authorized_keys"

###############################################################################
# Enable Remote Login
###############################################################################

remote_login_enabled() {
    sudo systemsetup -getremotelogin 2>/dev/null | grep -qi "on$"
}

enable_remote_login() {
    if remote_login_enabled; then
        log_success "Remote Login (sshd) is already enabled"
        return 0
    fi

    log_info "Enabling Remote Login..."

    if sudo systemsetup -setremotelogin on 2>/dev/null && remote_login_enabled; then
        log_success "Remote Login enabled"
        return 0
    fi

    # Since macOS 10.14, toggling Remote Login from the command line requires
    # the *calling terminal* to hold Full Disk Access. There is no way to grant
    # that from a script, so hand it back to the user rather than pretending.
    log_error "Could not enable Remote Login from the command line"
    echo
    log_info "macOS requires Full Disk Access for this. Either:"
    log_info "  a) System Settings → General → Sharing → turn on 'Remote Login', or"
    log_info "  b) System Settings → Privacy & Security → Full Disk Access →"
    log_info "     add your terminal app, restart it, and re-run this script"
    echo

    if ! ask "Continue anyway (install keys and hardening for later)?" n; then
        exit 1
    fi
}

###############################################################################
# Authorized keys
###############################################################################

count_keys() {
    [[ -f "$AUTH_KEYS" ]] || { echo 0; return; }
    # grep -c prints 0 and exits 1 on no match; capture first, then normalise,
    # so an empty file yields a single clean "0" for the numeric comparisons.
    local n
    n="$(grep -cE '^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-|sk-)' "$AUTH_KEYS" 2>/dev/null)" || n=0
    echo "${n:-0}"
}

append_key() {
    local key="$1"

    if [[ ! "$key" =~ ^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-|sk-) ]]; then
        log_error "Not a recognisable SSH public key — ignoring"
        return 1
    fi

    if [[ -f "$AUTH_KEYS" ]] && grep -qF "$key" "$AUTH_KEYS"; then
        log_info "Key already present — skipping"
        return 0
    fi

    printf '%s\n' "$key" >> "$AUTH_KEYS"
    log_success "Added key: $(echo "$key" | cut -d' ' -f3-)"
}

install_keys_from_github() {
    local user
    user="$(prompt_default "GitHub username" "")"
    [[ -z "$user" ]] && { log_warning "No username given — skipping"; return 0; }

    local keys
    if ! keys="$(curl -fsSL --max-time 15 "https://github.com/${user}.keys")" || [[ -z "$keys" ]]; then
        log_error "Could not fetch keys from https://github.com/${user}.keys"
        return 1
    fi

    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        append_key "$line" || true
    done <<< "$keys"
}

install_key_from_paste() {
    local key
    key="$(prompt_default "Paste the public key (one line)" "")"
    [[ -z "$key" ]] && { log_warning "Nothing pasted — skipping"; return 0; }
    append_key "$key" || true
}

install_key_from_file() {
    local path
    path="$(prompt_default "Path to a .pub file" "")"
    [[ -z "$path" ]] && { log_warning "No path given — skipping"; return 0; }

    # Expand a leading ~ so "~/.ssh/id_ed25519.pub" works when typed.
    path="${path/#\~/$HOME}"

    if [[ ! -f "$path" ]]; then
        log_error "No such file: $path"
        return 1
    fi

    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        append_key "$line" || true
    done < "$path"
}

setup_authorized_keys() {
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"

    log_info "Currently authorised keys: $(count_keys)"

    while true; do
        echo
        log_info "Add a public key from:"
        echo "  1) GitHub (fetches https://github.com/<user>.keys)"
        echo "  2) Paste it"
        echo "  3) A local .pub file"
        echo "  4) Done"
        echo

        local choice
        choice="$(prompt_default "Choice [1/2/3/4]" "4")"

        case "$choice" in
            1) install_keys_from_github || true ;;
            2) install_key_from_paste   || true ;;
            3) install_key_from_file    || true ;;
            4) break ;;
            *) log_warning "Invalid choice" ;;
        esac
    done

    log_info "Authorised keys now: $(count_keys)"
}

###############################################################################
# Hardening
###############################################################################

ensure_dropin_included() {
    # macOS 13+ ships sshd_config with an Include line at the top. On anything
    # older (or a hand-edited config) the drop-in would be silently ignored, so
    # verify rather than assume.
    if sudo grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/' "$SSHD_CONFIG"; then
        return 0
    fi

    log_warning "$SSHD_CONFIG does not include $SSHD_DROPIN_DIR"
    if ! ask "Add the Include line to the top of sshd_config?" y; then
        log_error "Without it the hardening drop-in has no effect — aborting hardening"
        return 1
    fi

    local backup
    backup="${SSHD_CONFIG}.macsetup.bak.$(date +%Y%m%d_%H%M%S)"
    sudo cp "$SSHD_CONFIG" "$backup"
    log_info "Backed up sshd_config to $backup"

    # sshd uses the FIRST value it obtains for each keyword, so the Include has
    # to come before everything else for the drop-in to win.
    local tmp
    tmp="$(mktemp)"
    {
        echo "Include /etc/ssh/sshd_config.d/*"
        sudo cat "$SSHD_CONFIG"
    } > "$tmp"
    sudo cp "$tmp" "$SSHD_CONFIG"
    rm -f "$tmp"
    log_success "Added Include directive to sshd_config"
}

write_hardening_dropin() {
    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
# Managed by MacSetup (server/ssh-setup.sh). Edits here survive macOS updates
# better than edits to /etc/ssh/sshd_config, which upgrades can replace.

# Keys only. Requires at least one entry in ~/.ssh/authorized_keys.
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no

# UsePAM must stay 'yes' on macOS — sshd depends on PAM for the session setup
# that grants access to the user's Keychain and home directory.
UsePAM yes

PermitRootLogin no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowAgentForwarding yes
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

    sudo mkdir -p "$SSHD_DROPIN_DIR"
    sudo cp "$tmp" "$SSHD_DROPIN"
    sudo chown root:wheel "$SSHD_DROPIN"
    sudo chmod 644 "$SSHD_DROPIN"
    rm -f "$tmp"

    log_success "Wrote $SSHD_DROPIN"
}

validate_and_reload() {
    log_info "Validating sshd configuration..."

    local output
    if ! output="$(sudo /usr/sbin/sshd -T 2>&1)"; then
        log_error "sshd rejected the configuration — NOT reloading"
        echo "$output" | tail -10 | sed 's/^/    /'
        log_warning "Removing the drop-in to leave sshd in a working state"
        sudo rm -f "$SSHD_DROPIN"
        return 1
    fi

    log_success "Configuration is valid"

    # Confirm the settings actually took effect before we rely on them.
    if echo "$output" | grep -qi '^passwordauthentication no'; then
        log_success "Password authentication is now disabled"
    else
        log_warning "sshd still reports password authentication as enabled"
    fi

    log_info "Reloading sshd..."
    if sudo launchctl kickstart -k system/com.openssh.sshd 2>/dev/null; then
        log_success "sshd reloaded"
    else
        log_warning "Could not reload sshd — it will pick up the change on next boot"
    fi
}

harden_sshd() {
    local keys
    keys="$(count_keys)"

    if [[ "$keys" -lt 1 ]]; then
        log_error "No authorised keys installed — refusing to disable password login"
        log_info "That combination would lock you out of this machine entirely."
        return 0
    fi

    echo
    log_warning "About to disable SSH password authentication."
    log_info "After this, the only way in over SSH is one of the $keys installed key(s)."
    log_info "Screen Sharing and the physical console are unaffected."
    echo

    if ! ask "Disable password authentication?" y; then
        log_info "Leaving password authentication enabled"
        return 0
    fi

    ensure_dropin_included || return 0
    write_hardening_dropin
    validate_and_reload || return 0

    echo
    log_warning "TEST THIS NOW, from another terminal, before closing this session:"
    log_info "  ssh $(whoami)@$(scutil --get LocalHostName 2>/dev/null || hostname).local"
    log_info "If it fails, undo with:  sudo rm $SSHD_DROPIN && sudo launchctl kickstart -k system/com.openssh.sshd"
}

main() {
    require_apple_silicon
    log_header "SSH Access — Key-Only"
    require_sudo

    enable_remote_login
    setup_authorized_keys
    harden_sshd

    echo
    log_success "SSH setup complete"
    log_info "Reach this machine at: $(whoami)@$(scutil --get LocalHostName 2>/dev/null || hostname).local"
}

main "$@"
