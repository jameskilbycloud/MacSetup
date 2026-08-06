# MacSetup

A collection of scripts to setup a factory fresh Mac with essential settings and software. The scripts are designed to be robust, user-friendly, and easily customizable.

## Features

- ✅ **Robust error handling** - Scripts continue gracefully when individual packages fail
- 🎨 **Colored output** - Clear visual feedback with color-coded messages
- 📝 **Detailed logging** - Know exactly what's happening during installation
- 🔧 **Easy customization** - Modify package lists in the configuration file
- 🧹 **Maintenance tools** - Keep your Homebrew installation clean and up-to-date
- 📱 **Mac App Store integration** - Install apps from the App Store via command line
- 🍺 **Homebrew best practices** - Proper formula vs cask separation

## Quick Start

### Option 1: One-command install (Recommended)

```shell
git clone https://github.com/jameskilbynet/MacSetup.git
cd MacSetup
chmod +x *.sh
./install.sh
```

`install.sh` will guide you through each step, letting you skip any that don't apply to your setup.

### Option 2: Run scripts individually

```shell
git clone https://github.com/jameskilbynet/MacSetup.git
cd MacSetup
chmod +x *.sh

./brew.sh                 # Install Homebrew and command-line tools
./brew-apps.sh            # Install GUI applications (and PowerShell)
./git-setup.sh            # Configure git with global gitignore
./zsh-setup.sh            # Setup Oh-My-Zsh with plugins and theme
./defaults.sh             # Apply macOS system settings
./mackup-setup.sh         # Sync app dotfiles via iCloud (Mackup)
./mas-apps.sh             # Install Mac App Store apps
```

### Option 3: Direct Download (no git required)

```shell
cd ~/Downloads

# Download and run the master installer.
# lib.sh is required — every other script sources it for shared logging helpers.
curl -O https://raw.githubusercontent.com/jameskilbynet/MacSetup/master/install.sh
curl -O https://raw.githubusercontent.com/jameskilbynet/MacSetup/master/lib.sh
curl -O https://raw.githubusercontent.com/jameskilbynet/MacSetup/master/brew.sh
curl -O https://raw.githubusercontent.com/jameskilbynet/MacSetup/master/brew-apps.sh
curl -O https://raw.githubusercontent.com/jameskilbynet/MacSetup/master/brew-maintenance.sh
curl -O https://raw.githubusercontent.com/jameskilbynet/MacSetup/master/git-setup.sh
curl -O https://raw.githubusercontent.com/jameskilbynet/MacSetup/master/gitignore_global
curl -O https://raw.githubusercontent.com/jameskilbynet/MacSetup/master/zsh-setup.sh
curl -O https://raw.githubusercontent.com/jameskilbynet/MacSetup/master/defaults.sh
curl -O https://raw.githubusercontent.com/jameskilbynet/MacSetup/master/mackup-setup.sh
curl -O https://raw.githubusercontent.com/jameskilbynet/MacSetup/master/mackup.cfg
curl -O https://raw.githubusercontent.com/jameskilbynet/MacSetup/master/mas-apps.sh

chmod +x *.sh
./install.sh
```

## Scripts Overview

### `brew.sh`
Installs Homebrew and essential command-line tools:

**DevOps & Infrastructure:**
- ansible, awscli, govc (vSphere CLI), helm
- kubernetes-cli, kubectx, k9s
- terraform, packer, vault (HashiCorp tools)
- wireguard-tools

**Modern CLI Tools:**
- btop, eza, fd, fzf, gh (GitHub CLI)
- git-delta, httpie, jq, lazygit
- ripgrep, tldr, zoxide

**System Utilities:**
- asciinema, htop, mackup, mas (Mac App Store CLI)
- ncdu, nmap, openssl, tmux, watch

**Programming Languages:**
- node, ruby, zsh

**Additional Features:**
- Handles Apple Silicon Mac PATH configuration automatically
- Individual package error handling with summary reporting

### `brew-apps.sh`
Installs GUI applications via Homebrew Cask, organized by category:

- **Browsers**: Firefox, Google Chrome
- **Development**: Claude, Docker, GitHub Desktop, iTerm2, Warp, Postman, VS Code
- **Creative & Productivity**: Adobe Creative Cloud, Moom (window management)
- **System Utilities**: Balena Etcher, Cloudflare WARP, iStat Menus, JDownloader, NordVPN, Remote Desktop Manager
- **Media & Entertainment**: OBS, Plex, Plexamp, VLC
- **Communication**: Signal
- **Enterprise**: VMware Horizon Client

PowerShell is installed directly from the official `.pkg` (the Homebrew cask was retired and the Microsoft tap formula is currently broken).

**Features:**
- Optional PowerShell module installation (VMware PowerCLI)
- Individual package error handling
- Installation summary with failed package list

### `mas-apps.sh`
Installs Mac App Store applications via the `mas` CLI. Requires you to be signed in to the App Store.

- **iHosts** — hosts-file editor

### `mackup-setup.sh`
Configures [Mackup](https://github.com/lra/mackup) to sync application dotfiles via iCloud Drive. Installs `~/.mackup.cfg`, then prompts to backup / restore / list / skip.

### `brew-maintenance.sh`
Maintenance utilities for keeping Homebrew healthy:
```shell
./brew-maintenance.sh update    # Update all packages
./brew-maintenance.sh cleanup   # Clean up old versions
./brew-maintenance.sh doctor    # Check for issues
./brew-maintenance.sh outdated  # List outdated packages
./brew-maintenance.sh backup    # Create package list backup
./brew-maintenance.sh full      # Run all maintenance tasks
```


### `git-setup.sh`
Configures Git with a comprehensive global gitignore file:

**Features:**
- Installs global gitignore file (~/.gitignore_global)
- Configures Git to use the global gitignore
- Blocks macOS system files (.DS_Store, etc.) from all repositories
- Sets default branch to 'main'
- Enables colored Git output
- Configures pull behavior

**Blocked Files:**
- macOS system files (.DS_Store, .AppleDouble, etc.)
- Thumbnail files (._*)
- IDE configuration (.idea/, .vscode/)
- Vim swap files

### `zsh-setup.sh`
Configures Oh-My-Zsh with plugins and Powerlevel10k theme:

**Features:**
- Installs Oh-My-Zsh framework
- Adds useful plugins (autosuggestions, syntax-highlighting, completions)
- Configures Powerlevel10k theme
- Adds DevOps-focused aliases (kubectl, terraform, ansible, git)
- Installs Hack Nerd Font for terminal icons
- Backs up existing configurations

**Included Aliases:**
- Kubernetes: `k`, `kgp`, `kgs`, `kgn`
- Terraform: `tf`, `tfi`, `tfp`, `tfa`
- Git: `gst`, `gpl`, `gps`, `gcm`
- Modern tools: Uses `bat`, `eza`, `fd`, `rg` if installed
- vSphere: `vcenter` (sets GOVC_URL)

### `defaults.sh`
Applies comprehensive macOS system preferences:

**Finder:**
- Show all file extensions, hidden files, path bar, status bar
- Full POSIX path in title bar
- Keep folders on top, search current folder by default
- Disable .DS_Store on network/USB volumes

**Keyboard & Input:**
- Enable key repeat, faster rates
- Disable auto-correct

**Screenshots:**
- Save to ~/Desktop/Screenshots
- PNG format, no shadows

**Dock:**
- Auto-hide with no delay
- Smaller size, no recent apps

**Performance:**
- Disable window animations
- Speed up Mission Control

## Customization

To customize which packages are installed:

1. **Edit `brew.sh`**: Modify the `formulas` array inside `install_formulas()` to add/remove CLI tools
2. **Edit `brew-apps.sh`**: Modify the category arrays inside `install_cask_apps()` to add/remove GUI applications
3. **Mac App Store apps**: Update the `MAS_APPS` associative array at the top of `mas-apps.sh`

### Example: Adding a new CLI tool
```bash
# In brew.sh, add to the formulas array:
local formulas=(
    # ... existing tools ...
    "neofetch"          # System information tool
)
```

### Example: Adding a new GUI app
```bash
# In brew-apps.sh, add to the appropriate category:
local dev_tools=(
    # ... existing tools ...
    "docker"            # Docker Desktop
)
```

## Prerequisites

- macOS (tested on recent versions)
- Internet connection
- For Mac App Store apps: signed in to your Apple ID

## What's New

### Improvements Made:
- ✅ Fixed typos ("inatall" → "install")
- ✅ Separated GUI apps into proper cask installations
- ✅ Added comprehensive error handling
- ✅ Implemented colored logging output
- ✅ Added progress indication and summaries
- ✅ Created modular, maintainable code structure
- ✅ Added maintenance utilities
- ✅ Improved Mac App Store integration
- ✅ Added Apple Silicon Mac support
- ✅ Separated PowerShell module installation
- ✅ Added package categorization and documentation

## Troubleshooting

### Common Issues

**Homebrew installation fails**
```bash
xcode-select --install  # Install Command Line Tools first
```

**Terraform installation conflict**
```bash
# If terraform is already installed from homebrew/core:
brew uninstall terraform
brew install hashicorp/tap/terraform
```

**Mac App Store apps fail**
- Sign in to the App Store before running the script
- The script will pause and wait for you to sign in

**MAS (Mac App Store CLI) errors**
- Make sure you are signed in to the App Store before running the script
- You can manually install: `mas install <app-id>`

**Permission errors**
- Never run with `sudo` - Homebrew installs in user space
- If you see permission errors, fix with: `sudo chown -R $(whoami) /opt/homebrew`

**Package not found**
```bash
brew search <package>     # Search for correct package name
brew info <package>       # Get package information
```

**Script execution issues**
```bash
chmod +x *.sh            # Ensure scripts are executable
```

## Contributing

Feel free to submit issues or pull requests to improve these scripts!

## License

This project is open source and available under the MIT License.
