#!/usr/bin/env bash

# MacSetup (server) — GitHub Actions self-hosted runner
#
# Installs the official runner into ~/actions-runner and registers it as a
# launchd service. Registration needs a short-lived token; if the GitHub CLI
# is authenticated this script mints one for you, otherwise you can paste one
# from the repo's Settings → Actions → Runners page.

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

RUNNER_DIR="$HOME/actions-runner"

json_field() {
    local field="$1"
    if command -v jq &>/dev/null; then
        jq -r ".$field // empty"
    else
        python3 -c "import sys,json; print(json.load(sys.stdin).get('$field',''))"
    fi
}

already_configured() {
    [[ -f "$RUNNER_DIR/.runner" ]]
}

download_runner() {
    local tag version asset url

    log_info "Resolving the latest runner release..."
    tag="$(curl -fsSL --max-time 20 \
        https://api.github.com/repos/actions/runner/releases/latest | json_field tag_name)"

    if [[ -z "$tag" ]]; then
        log_error "Could not determine the latest runner version from the GitHub API"
        log_info "Download manually: https://github.com/actions/runner/releases/latest"
        return 1
    fi

    version="${tag#v}"
    asset="actions-runner-osx-arm64-${version}.tar.gz"
    url="https://github.com/actions/runner/releases/download/${tag}/${asset}"

    mkdir -p "$RUNNER_DIR"

    # Unpack from a private temp dir. /tmp is world-writable, so a predictable
    # path lets another local process swap the tarball between download and
    # extraction — and this archive becomes code that runs your CI jobs.
    local tmp_dir
    tmp_dir="$(mktemp -d)" || { log_error "Could not create a temp directory"; return 1; }
    # shellcheck disable=SC2064  # expand tmp_dir now, not at trap time
    trap "rm -rf '$tmp_dir'" RETURN

    log_info "Downloading runner ${version} (osx-arm64)..."
    if ! curl -fL --progress-bar "$url" -o "$tmp_dir/$asset"; then
        log_error "Download failed: $url"
        return 1
    fi

    log_info "Extracting to $RUNNER_DIR..."
    if ! tar xzf "$tmp_dir/$asset" -C "$RUNNER_DIR"; then
        log_error "Could not extract the runner archive"
        return 1
    fi

    log_success "Runner ${version} installed to $RUNNER_DIR"
}

# Mint a registration token with gh, falling back to a manual paste.
get_registration_token() {
    local scope="$1"   # "repo" or "org"
    local target="$2"  # owner/repo, or org name

    if command -v gh &>/dev/null && gh auth status &>/dev/null; then
        local endpoint
        if [[ "$scope" == "repo" ]]; then
            endpoint="repos/${target}/actions/runners/registration-token"
        else
            endpoint="orgs/${target}/actions/runners/registration-token"
        fi

        local token
        if token="$(gh api -X POST "$endpoint" --jq .token 2>/dev/null)" && [[ -n "$token" ]]; then
            log_success "Minted a registration token via gh" >&2
            echo "$token"
            return 0
        fi
        log_warning "gh could not mint a token (needs admin rights on $target)" >&2
    fi

    log_info "Get a token from: Settings → Actions → Runners → New self-hosted runner" >&2
    prompt_default "Registration token" ""
}

configure_runner() {
    local scope target url token name labels

    echo
    log_info "Register this runner against a repository or an organisation?"
    echo "  1) A single repository"
    echo "  2) An organisation"
    echo

    local choice
    choice="$(prompt_default "Choice [1/2]" "1")"

    if [[ "$choice" == "2" ]]; then
        scope="org"
        target="$(prompt_default "Organisation name" "")"
        url="https://github.com/${target}"
    else
        scope="repo"
        target="$(prompt_default "Repository (owner/repo)" "")"
        url="https://github.com/${target}"
    fi

    if [[ -z "$target" ]]; then
        log_error "No target given — skipping registration"
        return 1
    fi

    token="$(get_registration_token "$scope" "$target")"
    if [[ -z "$token" ]]; then
        log_error "No registration token — skipping registration"
        return 1
    fi

    name="$(prompt_default "Runner name" "$(scutil --get LocalHostName 2>/dev/null || hostname)")"

    labels="$(prompt_default "Labels (comma-separated)" "self-hosted,macOS,arm64")"

    log_info "Registering runner '$name' with $url..."
    if ! ( cd "$RUNNER_DIR" && ./config.sh \
            --unattended \
            --url "$url" \
            --token "$token" \
            --name "$name" \
            --labels "$labels" \
            --replace ); then
        log_error "Runner registration failed"
        return 1
    fi

    log_success "Runner registered as '$name' [$labels]"
}

install_service() {
    log_info "Installing the runner as a launchd service..."

    if ! ( cd "$RUNNER_DIR" && ./svc.sh install ); then
        log_error "Could not install the runner service"
        return 1
    fi

    if ! ( cd "$RUNNER_DIR" && ./svc.sh start ); then
        log_error "Could not start the runner service"
        return 1
    fi

    log_success "Runner service installed and started"

    echo
    log_warning "The runner is a LaunchAgent — it only runs inside a logged-in session."
    warn_if_no_autologin
}

main() {
    require_apple_silicon
    log_header "GitHub Actions Self-Hosted Runner"

    log_info "This installs the official runner into $RUNNER_DIR and registers"
    log_info "it as a launchd service that starts with your login session."
    echo
    log_warning "A self-hosted runner executes whatever CI jobs its repo/org sends it,"
    log_warning "as your user, on this machine. Only attach it to repositories you"
    log_warning "trust — never to a public repo that accepts fork pull requests."
    echo

    if ! ask "Set up a GitHub Actions runner?" n; then
        log_info "Skipping the CI runner"
        exit 0
    fi

    if already_configured; then
        log_warning "A configured runner already exists at $RUNNER_DIR"
        log_info "Remove it first:  cd $RUNNER_DIR && ./svc.sh uninstall && ./config.sh remove"
        exit 0
    fi

    download_runner || exit 1
    configure_runner || exit 1
    install_service || exit 1

    echo
    log_success "CI runner setup complete"
    log_info "Manage it with:"
    echo "    cd $RUNNER_DIR && ./svc.sh status"
    echo "    cd $RUNNER_DIR && ./svc.sh stop | start | uninstall"
    echo "    Logs: $RUNNER_DIR/_diag/"
}

main "$@"
