#!/usr/bin/env bash

#Adapted from https://github.com/pathikrit/mac-setup-script/raw/master/defaults.sh

set -euo pipefail

if [[ -z "${CI:-}" ]]; then
  sudo -v # Ask for the administrator password upfront
  # Keep-alive: update existing `sudo` time stamp until script has finished
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# Close any open System Preferences panes, to prevent them from overriding settings we’re about to change
osascript -e 'tell application "System Preferences" to quit'

# Set Desktop as the default location for new Finder windows
defaults write com.apple.finder NewWindowTarget -string "PfDe"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Desktop/"

chflags nohidden ~/Library     # Show the ~/Library folder
sudo chflags nohidden /Volumes # Show the /Volumes folder

# Show full path in Finder title bar
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Avoid creating .DS_Store files on network or USB volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Automatically open a new Finder window when a volume is mounted
defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true

###############################################################################
# Finder & File Management
###############################################################################

# Show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show hidden files
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show status bar in Finder
defaults write com.apple.finder ShowStatusBar -bool true

# Show path bar in Finder
defaults write com.apple.finder ShowPathbar -bool true

# Keep folders on top when sorting
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# Search current folder by default
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Disable warning when changing file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Disable warning when emptying trash
defaults write com.apple.finder WarnOnEmptyTrash -bool false

###############################################################################
# Mouse
###############################################################################

# Enable right-click (secondary click) on Magic Mouse
defaults write com.apple.AppleMultitouchMouse MouseButtonMode -string "TwoButton"

# Enable right-click on trackpad
defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
defaults -currentHost write NSGlobalDomain com.apple.trackpad.enableSecondaryClick -bool true

###############################################################################
# Keyboard & Input
###############################################################################

# Enable key repeat (useful for vim/code editors)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Set faster key repeat rate
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Disable auto-correct
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

###############################################################################
# Screenshots
###############################################################################

# Save screenshots to Desktop/Screenshots
mkdir -p "${HOME}/Desktop/Screenshots"
defaults write com.apple.screencapture location -string "${HOME}/Desktop/Screenshots"

# Save screenshots as PNG (default) or JPG
defaults write com.apple.screencapture type -string "png"

# Disable shadow in screenshots
defaults write com.apple.screencapture disable-shadow -bool true

###############################################################################
# Dock
###############################################################################

# Auto-hide dock
defaults write com.apple.dock autohide -bool true

# Remove auto-hide delay
defaults write com.apple.dock autohide-delay -float 0

# Speed up animation
defaults write com.apple.dock autohide-time-modifier -float 0.5

# Set dock size
defaults write com.apple.dock tilesize -int 48

# Don't show recent applications
defaults write com.apple.dock show-recents -bool false

###############################################################################
# Performance
###############################################################################

# Disable animations when opening applications
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false

# Speed up Mission Control animations
defaults write com.apple.dock expose-animation-duration -float 0.1

###############################################################################
# Apply Changes
###############################################################################

# Restart affected applications.
# `|| true` because killall exits non-zero when no matching process is running,
# which under `set -e` would abort this script — and with it the rest of
# install.sh, skipping every step that follows.
killall Finder || true
killall Dock || true
killall SystemUIServer || true

echo "macOS defaults applied successfully! Some changes may require a logout/restart."
