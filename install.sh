#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Script configuration
CONFIG_DIR="$HOME/.config"
FONT_DIR="$HOME/.local/share/fonts"
INSTALL_DIR=$(dirname "$(readlink -f "$0")")

# Function to print colored output
print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
}

# Check if running with sudo/root
if [ "$EUID" -ne 0 ]; then 
    print_msg "$RED" "Please run as root or with sudo"
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install packages based on the package manager
install_package() {
    local package=$1
    
    if command_exists apt-get; then
        apt-get install -y "$package"
    elif command_exists pacman; then
        pacman -S --noconfirm "$package"
    elif command_exists dnf; then
        dnf install -y "$package"
    else
        print_msg "$RED" "No supported package manager found!"
        exit 1
    fi
}

# Check and install dependencies
install_dependencies() {
    print_msg "$BLUE" "Checking and installing dependencies..."
    
    local dependencies=(
        "i3"
        "i3-wm"
        "polybar"
        "picom"
        "rofi"
        "feh"
        "lightdm"
        "web-greeter"
        "nodejs"
        "npm"
        "firefox"
        "xfce4-terminal"
        "bluez"
        "bluez-utils"
        "jq"          # For weather script
        "curl"        # For weather script
        "light"       # For brightness control
        "pulseaudio"  # For volume control
    )

    for dep in "${dependencies[@]}"; do
        if ! command_exists "$dep"; then
            print_msg "$YELLOW" "Installing $dep..."
            install_package "$dep"
        fi
    done
}

# Install fonts
install_fonts() {
    print_msg "$BLUE" "Installing fonts..."
    
    # Create fonts directory if it doesn't exist
    mkdir -p "$FONT_DIR"
    
    # Copy fonts
    cp -r "$INSTALL_DIR/fonts/"* "$FONT_DIR/"
    
    # Refresh font cache
    fc-cache -f
}

# Install configurations
install_configs() {
    print_msg "$BLUE" "Installing configurations..."
    
    # Create config directories
    mkdir -p "$CONFIG_DIR"/{i3,polybar,picom}
    
    # i3 config
    cp -r "$INSTALL_DIR/src/i3/"* "$CONFIG_DIR/i3/"
    
    # Polybar config and scripts
    cp -r "$INSTALL_DIR/src/polybar/"* "$CONFIG_DIR/polybar/"
    chmod +x "$CONFIG_DIR/polybar/scripts/"**/*.sh
    
    # Picom config
    cp -r "$INSTALL_DIR/src/picom/"* "$CONFIG_DIR/picom/"
    
    # Firefox customization
    local firefox_dir="$HOME/.mozilla/firefox"
    if [ -d "$firefox_dir" ]; then
        # Find default profile directory
        local profile_dir=$(find "$firefox_dir" -type d -name "*.default-release" -print -quit)
        if [ -n "$profile_dir" ]; then
            mkdir -p "$profile_dir/chrome"
            cp "$INSTALL_DIR/src/firefox/chrome/"* "$profile_dir/chrome/"
            cp "$INSTALL_DIR/src/firefox/user.js" "$profile_dir/"
        fi
    fi
    
    # Web-greeter theme
    if [ -d "/usr/share/web-greeter/themes/" ]; then
        cp -r "$INSTALL_DIR/src/web-greeter/gruvbox" "/usr/share/web-greeter/themes/"
        # Set as default theme
        sed -i 's/^theme = .*/theme = "gruvbox"/' /etc/lightdm/web-greeter.yml
    fi
}

# Set correct permissions
set_permissions() {
    print_msg "$BLUE" "Setting permissions..."
    
    # Make scripts executable
    find "$CONFIG_DIR/polybar/scripts" -type f -name "*.sh" -exec chmod +x {} \;
    
    # Set ownership
    chown -R "$SUDO_USER:$SUDO_USER" "$CONFIG_DIR"
    chown -R "$SUDO_USER:$SUDO_USER" "$FONT_DIR"
}

# Cleanup existing installation
cleanup() {
    print_msg "$BLUE" "Cleaning up existing installation..."
    
    # Remove existing configs
    rm -rf "$CONFIG_DIR"/{i3,polybar,picom}
    
    # Remove existing web-greeter theme
    rm -rf "/usr/share/web-greeter/themes/gruvbox"
}

# Main installation function
main() {
    print_msg "$GREEN" "Starting installation..."
    
    # Cleanup existing installation
    cleanup
    
    # Install required dependencies
    install_dependencies
    
    # Install fonts
    install_fonts
    
    # Install configurations
    install_configs
    
    # Set permissions
    set_permissions
    
    print_msg "$GREEN" "Installation completed successfully!"
    print_msg "$YELLOW" "Please log out and log back in for changes to take effect."
}

# Run main installation
main