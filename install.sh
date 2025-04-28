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
TMP_DIR="/tmp/i3-dot-install-$$" # Temporary directory for cloning

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

# Ensure SUDO_USER is set, even if run directly as root
if [ -z "$SUDO_USER" ]; then
    if [ "$(logname)" ]; then
        SUDO_USER=$(logname)
    else
        print_msg "$RED" "Cannot determine the original user. Please run with sudo."
        exit 1
    fi
    print_msg "$YELLOW" "Running as root, setting user to $SUDO_USER"
    # Re-export HOME for the original user if needed for config paths
    export HOME=$(eval echo ~$SUDO_USER)
    CONFIG_DIR="$HOME/.config"
    FONT_DIR="$HOME/.local/share/fonts"
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install packages based on the package manager
install_package() {
    local package=$1
    print_msg "$YELLOW" "Attempting to install $package..."

    if command_exists apt-get; then
        apt-get update > /dev/null # Update quietly
        apt-get install -y "$package"
    elif command_exists pacman; then
        pacman -Syu --noconfirm "$package"
    elif command_exists dnf; then
        dnf install -y "$package"
    elif command_exists zypper; then
        zypper install -y "$package"
    else
        print_msg "$RED" "No supported package manager (apt, pacman, dnf, zypper) found!"
        exit 1
    fi

    if [ $? -ne 0 ]; then
        print_msg "$RED" "Failed to install $package."
        # Optionally exit on failure: exit 1
    else
        print_msg "$GREEN" "$package installed successfully."
    fi
}

# Check and install dependencies
install_dependencies() {
    print_msg "$BLUE" "Checking and installing dependencies..."

    # Core components
    local core_deps=(
        "i3-wm"         # i3 Window Manager (often named i3-wm or just i3)
        "polybar"
        "picom"
        "rofi"
        "feh"           # Background setter
        "lightdm"       # Display Manager
        "git"           # For cloning web-greeter
        "make"          # For building web-greeter
        "gcc"           # For building web-greeter
        "nodejs"        # Often needed by web-greeter themes or build processes
        "npm"           # Often needed by web-greeter themes or build processes
        "typescript"    # Required for compiling web-greeter themes
        "firefox"
        "xfce4-terminal" # Or your preferred terminal
        "bluez"         # Bluetooth stack
        "bluez-utils"   # Bluetooth utilities
        "jq"            # For weather script
        "curl"          # For weather script
        "pipewire"      # Audio server (or pulseaudio/alsa-utils if preferred)
        "pavucontrol"   # Volume control GUI for PipeWire/PulseAudio
        "fontconfig"    # For managing fonts (fc-cache)
        "rsync"         # Required for web-greeter installation
        "python-pyqt5"  # Required for web-greeter build (provides pyrcc5)
    )

    # Build dependencies for web-greeter
    # Each distro has different package names, detect and install accordingly
    if command_exists pacman; then
        # Arch Linux dependencies
        local build_deps=(
            "webkit2gtk"
            "base-devel"
            "lightdm"
        )
    elif command_exists apt-get; then
        # Debian/Ubuntu dependencies
        local build_deps=(
            "liblightdm-gobject-1-dev"
            "libwebkit2gtk-4.0-dev"
        )
    elif command_exists dnf; then
        # Fedora dependencies
        local build_deps=(
            "lightdm-devel"
            "webkitgtk4-devel"
        )
    else
        print_msg "$RED" "Unsupported distribution for web-greeter build dependencies"
        exit 1
    fi

    # Combine dependency lists
    local dependencies=("${core_deps[@]}" "${build_deps[@]}")

    for dep in "${dependencies[@]}"; do
        # Check if the command/package likely exists before trying to install
        # This is a basic check; package names might differ from command names
        local check_cmd=${dep%%-dev} # Simple heuristic to check base command
        check_cmd=${check_cmd%%-devel}
        if ! command_exists "$check_cmd" && ! dpkg -s "$dep" &> /dev/null && ! rpm -q "$dep" &> /dev/null && ! pacman -Q "$dep" &> /dev/null; then
             install_package "$dep"
        else
             print_msg "$GREEN" "$dep seems to be installed."
        fi
    done

    # Special check for i3 (package name might be 'i3' or 'i3-wm')
    if ! command_exists i3; then
        print_msg "$YELLOW" "i3 command not found, attempting to install 'i3' package..."
        install_package "i3" || install_package "i3-wm"
    fi
}

# Install web-greeter from source
install_web_greeter() {
    print_msg "$BLUE" "Installing web-greeter from source..."
    mkdir -p "$TMP_DIR"
    if [ ! -d "$TMP_DIR" ]; then
        print_msg "$RED" "Failed to create temporary directory $TMP_DIR"
        exit 1
    fi
    cd "$TMP_DIR" || exit 1

    print_msg "$YELLOW" "Cloning web-greeter repository with submodules..."
    git clone --recursive https://github.com/JezerM/web-greeter.git
    if [ $? -ne 0 ]; then
        print_msg "$RED" "Failed to clone web-greeter repository."
        rm -rf "$TMP_DIR"
        exit 1
    fi

    cd web-greeter || exit 1

    print_msg "$YELLOW" "Installing web-greeter..."
    if ! make install; then
        print_msg "$RED" "Failed to install web-greeter."
        rm -rf "$TMP_DIR"
        exit 1
    fi

    print_msg "$GREEN" "web-greeter installed successfully."
    cd "$INSTALL_DIR" # Go back to original script dir
    rm -rf "$TMP_DIR" # Clean up
}

# Install fonts
install_fonts() {
    print_msg "$BLUE" "Installing fonts..."
    local user_font_dir=$(eval echo ~$SUDO_USER)/.local/share/fonts

    # Create fonts directory if it doesn't exist
    mkdir -p "$user_font_dir"

    # Copy fonts
    print_msg "$YELLOW" "Copying fonts to $user_font_dir..."
    cp -r "$INSTALL_DIR/fonts/"* "$user_font_dir/"

    # Refresh font cache
    print_msg "$YELLOW" "Refreshing font cache..."
    fc-cache -f -v
    if [ $? -ne 0 ]; then
        print_msg "$RED" "fc-cache command failed. Fonts might not be immediately available."
    else
        print_msg "$GREEN" "Font cache refreshed."
    fi
}

# Install configurations
install_configs() {
    print_msg "$BLUE" "Installing configurations..."
    local user_config_dir=$(eval echo ~$SUDO_USER)/.config
    local user_home=$(eval echo ~$SUDO_USER)

    # Create config directories owned by the user
    mkdir -p "$user_config_dir"/{i3,polybar/scripts,picom}
    chown -R "$SUDO_USER:$SUDO_USER" "$user_config_dir"

    # i3 config
    print_msg "$YELLOW" "Copying i3 config..."
    cp "$INSTALL_DIR/src/i3/config" "$user_config_dir/i3/"

    # Polybar config and scripts
    print_msg "$YELLOW" "Copying Polybar config and scripts..."
    cp "$INSTALL_DIR/src/polybar/config.ini" "$user_config_dir/polybar/"
    cp -r "$INSTALL_DIR/src/polybar/scripts/"* "$user_config_dir/polybar/scripts/"
    chmod +x "$user_config_dir/polybar/scripts/"**/*.sh

    # Picom config
    print_msg "$YELLOW" "Copying Picom config..."
    cp "$INSTALL_DIR/src/picom/picom.conf" "$user_config_dir/picom/"

    # Firefox customization
    local firefox_dir="$user_home/.mozilla/firefox"
    if [ -d "$firefox_dir" ]; then
        print_msg "$YELLOW" "Attempting Firefox customization..."
        # Find default profile directory more robustly
        local profile_dir=$(find "$firefox_dir" -maxdepth 1 -type d -name "*.default-release" -print -quit)
        if [ -z "$profile_dir" ]; then
             profile_dir=$(find "$firefox_dir" -maxdepth 1 -type d -name "*.default" -print -quit)
        fi

        if [ -n "$profile_dir" ] && [ -d "$profile_dir" ]; then
            print_msg "$YELLOW" "Found Firefox profile: $profile_dir"
            mkdir -p "$profile_dir/chrome"
            cp "$INSTALL_DIR/src/firefox/chrome/userChrome.css" "$profile_dir/chrome/"
            cp "$INSTALL_DIR/src/firefox/chrome/userContent.css" "$profile_dir/chrome/"
            cp "$INSTALL_DIR/src/firefox/user.js" "$profile_dir/"
            chown -R "$SUDO_USER:$SUDO_USER" "$profile_dir/chrome" "$profile_dir/user.js"
            print_msg "$GREEN" "Firefox customization applied."
        else
            print_msg "$YELLOW" "Could not find Firefox default profile directory. Skipping Firefox customization."
        fi
    else
        print_msg "$YELLOW" "Firefox directory not found. Skipping Firefox customization."
    fi

    # Web-greeter theme
    local web_greeter_themes_dir="/usr/share/web-greeter/themes"
    if [ -d "$web_greeter_themes_dir" ]; then
        print_msg "$YELLOW" "Copying web-greeter theme..."
        cp -r "$INSTALL_DIR/src/web-greeter/gruvbox" "$web_greeter_themes_dir/"
        print_msg "$GREEN" "Web-greeter theme copied."

        # Set web-greeter theme in its config
        local web_greeter_config="/etc/lightdm/web-greeter.yml"
        if [ -f "$web_greeter_config" ]; then
            print_msg "$YELLOW" "Setting web-greeter theme to gruvbox in $web_greeter_config..."
            # Use sed to change the theme, handling comments and existing settings
            sed -i 's/^[# ]*theme:.*/theme: gruvbox/' "$web_greeter_config"
            # If the theme line doesn't exist, add it
            if ! grep -q "^theme: gruvbox" "$web_greeter_config"; then
                echo "theme: gruvbox" >> "$web_greeter_config"
            fi
            print_msg "$GREEN" "Web-greeter theme set."
        else
            print_msg "$YELLOW" "Web-greeter config ($web_greeter_config) not found. Cannot set theme automatically."
        fi
    else
        print_msg "$RED" "Web-greeter themes directory ($web_greeter_themes_dir) not found. Was web-greeter installed correctly?"
    fi

    # Ensure all copied config files are owned by the user
    chown -R "$SUDO_USER:$SUDO_USER" "$user_config_dir"
}

# Configure LightDM to use web-greeter
configure_lightdm() {
    print_msg "$BLUE" "Configuring LightDM..."
    local lightdm_config="/etc/lightdm/lightdm.conf"
    local lightdm_config_dir="/etc/lightdm"
    local seat_defaults="[Seat:*]"

    if [ ! -d "$lightdm_config_dir" ]; then
        print_msg "$YELLOW" "LightDM config directory ($lightdm_config_dir) not found. Creating it."
        mkdir -p "$lightdm_config_dir"
    fi

    # Ensure the config file exists
    if [ ! -f "$lightdm_config" ]; then
        print_msg "$YELLOW" "LightDM config file ($lightdm_config) not found. Creating a basic one."
        echo -e "$seat_defaults\n" > "$lightdm_config"
    fi

    # Ensure the [Seat:*] section exists
    if ! grep -q "^\\[Seat:\\*\\]" "$lightdm_config"; then
        print_msg "$YELLOW" "$seat_defaults section not found in $lightdm_config. Adding it."
        echo -e "\n$seat_defaults" >> "$lightdm_config"
    fi

    # Set the greeter-session
    local greeter_setting="greeter-session=web-greeter"
    if grep -q "^\\[Seat:\\*\\]" "$lightdm_config"; then
        # Check if greeter-session is already set under [Seat:*]
        if grep -A 5 "^\\[Seat:\\*\\]" "$lightdm_config" | grep -q "^greeter-session="; then
             # If it exists, modify it (handle commented out lines)
             sed -i "/^\\[Seat:\\*\\]/,/^\\[/ s/^[# ]*greeter-session=.*/$greeter_setting/" "$lightdm_config"
             print_msg "$YELLOW" "Updated existing greeter-session setting in $lightdm_config."
        else
             # If it doesn't exist, add it under [Seat:*]
             sed -i "/^\\[Seat:\\*\\]/a $greeter_setting" "$lightdm_config"
             print_msg "$YELLOW" "Added greeter-session setting to $lightdm_config."
        fi
    else
         print_msg "$RED" "Could not find or add $seat_defaults section in $lightdm_config. Manual configuration required."
         return 1
    fi

    print_msg "$GREEN" "LightDM configured to use web-greeter."

    # Enable and start LightDM service (optional, depends on system)
    if command_exists systemctl; then
        print_msg "$YELLOW" "Attempting to enable LightDM service..."
        systemctl enable lightdm
        if [ $? -eq 0 ]; then
            print_msg "$GREEN" "LightDM service enabled."
        else
            print_msg "$RED" "Failed to enable LightDM service. You might need to do this manually."
        fi
    else
        print_msg "$YELLOW" "systemctl not found. Cannot enable LightDM service automatically."
    fi
}

# Set correct permissions (mostly handled within functions now, but double-check user dirs)
set_permissions() {
    print_msg "$BLUE" "Finalizing permissions..."
    local user_config_dir=$(eval echo ~$SUDO_USER)/.config
    local user_font_dir=$(eval echo ~$SUDO_USER)/.local/share/fonts

    # Ensure user owns their config and font directories
    if [ -d "$user_config_dir" ]; then
        chown -R "$SUDO_USER:$SUDO_USER" "$user_config_dir"
    fi
     if [ -d "$user_font_dir" ]; then
        chown -R "$SUDO_USER:$SUDO_USER" "$user_font_dir"
    fi

    # Make polybar scripts executable (redundant check, but safe)
    if [ -d "$user_config_dir/polybar/scripts" ]; then
        find "$user_config_dir/polybar/scripts" -type f -name "*.sh" -exec chmod +x {} \;
    fi
    print_msg "$GREEN" "Permissions finalized."
}

# Cleanup existing installation (optional, use with caution)
cleanup() {
    print_msg "$YELLOW" "Cleaning up previous configuration files (if they exist)..."
    local user_config_dir=$(eval echo ~$SUDO_USER)/.config

    # Remove specific config directories managed by this script
    rm -rf "$user_config_dir/i3"
    rm -rf "$user_config_dir/polybar"
    rm -rf "$user_config_dir/picom"

    # Remove existing web-greeter theme if copied by this script
    # Be careful not to remove system-provided themes
    rm -rf "/usr/share/web-greeter/themes/gruvbox"

    print_msg "$GREEN" "Cleanup finished."
}

# Main installation function
main() {
    print_msg "$GREEN" "Starting i3 Dotfiles Installation..."

    # Optional: Ask user before cleaning up
    # read -p "Do you want to remove existing i3, polybar, picom configs? [y/N] " -n 1 -r
    # echo
    # if [[ $REPLY =~ ^[Yy]$ ]]; then
    #     cleanup
    # fi
    cleanup # Run cleanup by default as per original script logic

    # Install required dependencies
    install_dependencies

    # Install web-greeter from source
    install_web_greeter

    # Install fonts
    install_fonts

    # Install configurations (dotfiles, themes)
    install_configs

    # Configure LightDM to use the new greeter
    configure_lightdm

    # Set final permissions
    set_permissions

    print_msg "$GREEN" "Installation completed successfully!"
    print_msg "$YELLOW" "Please REBOOT your system for all changes, especially LightDM, to take effect properly."
    print_msg "$YELLOW" "After rebooting, select 'i3' from the login screen session menu (if available)."
}

# Run main installation
main
