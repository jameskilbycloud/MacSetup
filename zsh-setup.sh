#!/usr/bin/env bash

# MacSetup Oh-My-Zsh Configuration Script
# Installs Oh-My-Zsh with useful plugins and Powerlevel10k theme

set -euo pipefail  # Exit on error, undefined vars, pipe failures

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f "$SCRIPT_DIR/lib.sh" ]]; then
    echo "Error: missing $SCRIPT_DIR/lib.sh (required by this script)" >&2
    exit 1
fi
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Check if zsh is installed
check_zsh() {
    if ! command -v zsh &> /dev/null; then
        log_error "Zsh is not installed. Please run brew.sh first."
        exit 1
    fi
    log_info "Zsh found at: $(which zsh)"
}

# Set zsh as default shell
set_default_shell() {
    if [ "$SHELL" != "$(which zsh)" ]; then
        log_info "Setting zsh as default shell..."
        chsh -s "$(which zsh)"
        log_success "Default shell set to zsh (restart terminal to apply)"
    else
        log_info "Zsh is already the default shell"
    fi
}

# Install Oh-My-Zsh
install_oh_my_zsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log_warning "Oh-My-Zsh is already installed"
        read -p "Do you want to reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
        log_info "Backing up existing .oh-my-zsh to .oh-my-zsh.backup..."
        mv "$HOME/.oh-my-zsh" "$HOME/.oh-my-zsh.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    log_info "Installing Oh-My-Zsh..."
    if sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
        log_success "Oh-My-Zsh installed successfully"
    else
        log_error "Failed to install Oh-My-Zsh"
        exit 1
    fi
}

# Install Oh-My-Zsh plugins
install_plugins() {
    log_info "Installing Oh-My-Zsh plugins..."
    
    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    
    # zsh-autosuggestions
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
        log_info "Installing zsh-autosuggestions..."
        git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
        log_success "Installed zsh-autosuggestions"
    else
        log_info "zsh-autosuggestions already installed"
    fi
    
    # zsh-syntax-highlighting
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
        log_info "Installing zsh-syntax-highlighting..."
        git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
        log_success "Installed zsh-syntax-highlighting"
    else
        log_info "zsh-syntax-highlighting already installed"
    fi
    
    # zsh-completions
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-completions" ]; then
        log_info "Installing zsh-completions..."
        git clone https://github.com/zsh-users/zsh-completions "$ZSH_CUSTOM/plugins/zsh-completions"
        log_success "Installed zsh-completions"
    else
        log_info "zsh-completions already installed"
    fi
}

# Install Powerlevel10k theme
install_theme() {
    log_info "Installing Powerlevel10k theme..."
    
    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    
    if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
        log_success "Installed Powerlevel10k theme"
    else
        log_info "Powerlevel10k already installed"
    fi
}

# Configure .zshrc
configure_zshrc() {
    log_info "Configuring .zshrc..."
    
    local ZSHRC="$HOME/.zshrc"
    
    # Backup existing .zshrc
    if [ -f "$ZSHRC" ]; then
        cp "$ZSHRC" "$ZSHRC.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing .zshrc"
    fi
    
    # Update theme
    if grep -q "^ZSH_THEME=" "$ZSHRC"; then
        sed -i.bak 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$ZSHRC"
        log_success "Updated theme to Powerlevel10k"
    fi
    
    # Update plugins
    if grep -q "^plugins=" "$ZSHRC"; then
        sed -i.bak 's/^plugins=.*/plugins=(git docker kubectl terraform ansible aws zsh-autosuggestions zsh-syntax-highlighting zsh-completions)/' "$ZSHRC"
        log_success "Updated plugins list"
    fi
    
    # Ensure Homebrew is on PATH for interactive (non-login) shells
    if ! grep -q "brew shellenv" "$ZSHRC"; then
        echo '' >> "$ZSHRC"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$ZSHRC"
        log_success "Added Homebrew shellenv to .zshrc"
    fi

    # Add custom aliases if not already present
    if ! grep -q "# MacSetup Custom Aliases" "$ZSHRC"; then
        cat >> "$ZSHRC" << 'EOF'

###############################################################################
# MacSetup Custom Aliases
###############################################################################

# Kubernetes aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'

# Terraform aliases
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'

# Ansible aliases
alias ap='ansible-playbook'
alias av='ansible-vault'

# Git aliases (additional to oh-my-zsh git plugin)
alias gst='git status'
alias gpl='git pull'
alias gps='git push'
alias gcm='git commit -m'
alias gco='git checkout'
alias gcb='git checkout -b'

# vSphere/govc aliases
alias vcenter='export GOVC_URL=uk-bhr-p-vc-1.jameskilby.cloud'

# Modern CLI replacements (if installed)
if command -v bat &> /dev/null; then alias cat='bat'; fi
if command -v eza &> /dev/null; then 
    alias ls='eza --icons'
    alias ll='eza -la --icons'
    alias lt='eza --tree --level=2 --icons'
fi
if command -v fd &> /dev/null; then alias find='fd'; fi
if command -v rg &> /dev/null; then alias grep='rg'; fi
if command -v btop &> /dev/null; then alias top='btop'; fi

# Utility aliases
alias myip='curl -s ifconfig.me'
alias ports='lsof -PiTCP -sTCP:LISTEN'
alias cleanup='brew cleanup && brew autoremove'
alias update='brew update && brew upgrade && brew cleanup'

# Navigation aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Directory shortcuts
alias dl='cd ~/Downloads'
alias dt='cd ~/Desktop'
alias projects='cd ~/Github'

EOF
        log_success "Added custom aliases to .zshrc"
    else
        log_info "Custom aliases already present in .zshrc"
    fi
}

# Install Nerd Font for Powerlevel10k
install_nerd_font() {
    log_info "Checking for Nerd Font..."
    
    if ! brew list --cask font-hack-nerd-font &> /dev/null; then
        log_info "Installing Hack Nerd Font..."
        brew install --cask font-hack-nerd-font
        log_success "Installed Hack Nerd Font"
        log_warning "Set your terminal font to 'Hack Nerd Font' for best results"
    else
        log_info "Hack Nerd Font already installed"
    fi
}

# Main execution
main() {
    log_info "Starting Oh-My-Zsh setup..."
    echo
    
    check_zsh
    set_default_shell
    install_oh_my_zsh
    install_plugins
    install_theme
    configure_zshrc
    install_nerd_font
    
    echo
    log_success "Oh-My-Zsh setup completed!"
    echo
    log_info "Next steps:"
    echo "  1. Restart your terminal or run: source ~/.zshrc"
    echo "  2. Run 'p10k configure' to set up your Powerlevel10k prompt"
    echo "  3. Set your terminal font to 'Hack Nerd Font' for icons"
    echo
    log_warning "Some changes require a terminal restart to take effect"
}

# Run main function
main "$@"
