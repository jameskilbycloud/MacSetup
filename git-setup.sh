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

# Copy gitignore_global to home directory
log_info "Installing global gitignore..."
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
echo -e "  • Global gitignore installed at ~/.gitignore_global"
echo -e "  • Git configured to exclude .DS_Store and other macOS files globally"
echo -e "  • Default branch set to 'main'"
echo -e "  • Colored output enabled"
echo ""
echo -e "${BLUE}Note:${NC} This will prevent .DS_Store files from being tracked in any git repository on this machine."
