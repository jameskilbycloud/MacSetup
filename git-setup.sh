#!/usr/bin/env bash

# MacSetup Git Configuration
# Configures global git settings including gitignore

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f "$SCRIPT_DIR/lib.sh" ]]; then
    echo "Error: missing $SCRIPT_DIR/lib.sh (required by this script)" >&2
    exit 1
fi
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

log_header "Git Configuration Setup"

# Check if gitignore_global exists
if [ ! -f "$SCRIPT_DIR/gitignore_global" ]; then
    log_error "gitignore_global file not found in $SCRIPT_DIR"
    exit 1
fi

# Configure git identity — without this, commits on a fresh Mac fail or get
# attributed to a guessed hostname address. Existing values are left alone.
configure_identity() {
    local current_name current_email

    current_name=$(git config --global user.name || true)
    current_email=$(git config --global user.email || true)

    if [[ -n "$current_name" && -n "$current_email" ]]; then
        log_info "Git identity already set: $current_name <$current_email>"
        return 0
    fi

    # Non-interactive (CI, piped input): warn and move on rather than hang.
    if [[ ! -t 0 ]]; then
        log_warning "No git identity set and no TTY to prompt — skipping."
        log_info "Set it later: git config --global user.name 'Your Name'"
        return 0
    fi

    if [[ -z "$current_name" ]]; then
        read -rp "$(echo -e "${YELLOW}?${NC} Git user.name (blank to skip): ")" current_name
        if [[ -n "$current_name" ]]; then
            git config --global user.name "$current_name"
            log_success "Set user.name to '$current_name'"
        else
            log_warning "Skipped user.name"
        fi
    fi

    if [[ -z "$current_email" ]]; then
        read -rp "$(echo -e "${YELLOW}?${NC} Git user.email (blank to skip): ")" current_email
        if [[ -n "$current_email" ]]; then
            git config --global user.email "$current_email"
            log_success "Set user.email to '$current_email'"
        else
            log_warning "Skipped user.email"
        fi
    fi
}

configure_identity

# Copy gitignore_global to home directory
log_info "Installing global gitignore..."
if [[ -f "$HOME/.gitignore_global" ]] \
   && ! cmp -s "$SCRIPT_DIR/gitignore_global" "$HOME/.gitignore_global"; then
    log_warning "Existing ~/.gitignore_global differs — backing up to ~/.gitignore_global.bak"
    cp "$HOME/.gitignore_global" "$HOME/.gitignore_global.bak"
fi
cp "$SCRIPT_DIR/gitignore_global" "$HOME/.gitignore_global"
log_success "Copied gitignore_global to ~/.gitignore_global"

# Configure git to use the global gitignore
log_info "Configuring git to use global gitignore..."
git config --global core.excludesfile "$HOME/.gitignore_global"
log_success "Git configured to use ~/.gitignore_global"

# Optional: Configure other useful git settings
log_info "Configuring additional git settings..."

# Set default branch name to main
if ! git config --global init.defaultBranch &>/dev/null; then
    git config --global init.defaultBranch main
    log_success "Set default branch name to 'main'"
fi

# Enable color output
git config --global color.ui auto
log_success "Enabled colored git output"

# Configure pull behavior
if ! git config --global pull.rebase &>/dev/null; then
    git config --global pull.rebase false
    log_success "Configured pull behavior (merge)"
fi

log_header "Git Configuration Complete"

echo -e "${GREEN}Summary:${NC}"
final_name=$(git config --global user.name || true)
final_email=$(git config --global user.email || true)
if [[ -n "$final_name" && -n "$final_email" ]]; then
    echo -e "  • Git identity: $final_name <$final_email>"
else
    echo -e "  • ${YELLOW}Git identity not set${NC} — run: git config --global user.name 'Your Name'"
fi
echo -e "  • Global gitignore installed at ~/.gitignore_global"
echo -e "  • Git configured to exclude .DS_Store and other macOS files globally"
echo -e "  • Default branch set to 'main'"
echo -e "  • Colored output enabled"
echo ""
echo -e "${BLUE}Note:${NC} This will prevent .DS_Store files from being tracked in any git repository on this machine."
