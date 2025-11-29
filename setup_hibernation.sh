#!/bin/bash

# ==============================================================================
# Ubuntu Hibernation Setup Script (Swap Partition Method)
# ==============================================================================
#
# This script automates the process of enabling hibernation on Ubuntu and its
# derivatives by configuring GRUB and initramfs to use a swap partition.
#
# Features:
#   - Configures GRUB and initramfs for hibernation
#   - Detects laptops and configures lid-close to hibernate
#   - Supports Regolith desktop environment
#   - Creates polkit rules for passwordless hibernation
#
# WARNING: This script modifies critical system files. While it includes
#          safety checks and backups, please ensure you have backed up your
#          important data before running it.
#
# USAGE:
# 1. Save this script as 'setup-hibernate.sh'.
# 2. Make it executable: chmod +x setup-hibernate.sh
# 3. Run it with sudo:   sudo ./setup-hibernate.sh
#
# ==============================================================================

# --- Configuration & Colors ---
set -e # Exit immediately if a command exits with a non-zero status.
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Helper Functions ---
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

# --- Detection Functions ---

is_laptop() {
    # Method 1: Check chassis type
    # Values 8, 9, 10, 11, 14 indicate portable devices
    # 8=Portable, 9=Laptop, 10=Notebook, 11=Hand Held, 14=Sub Notebook
    if [[ -f /sys/class/dmi/id/chassis_type ]]; then
        local chassis_type
        chassis_type=$(cat /sys/class/dmi/id/chassis_type)
        if [[ "$chassis_type" =~ ^(8|9|10|11|14)$ ]]; then
            return 0
        fi
    fi

    # Method 2: Check for lid switch
    if [[ -d /proc/acpi/button/lid ]]; then
        return 0
    fi

    # Method 3: Check for battery
    if ls /sys/class/power_supply/BAT* &>/dev/null; then
        return 0
    fi

    return 1
}

is_regolith() {
    # Check for regolith config directory (works even when running as root)
    local user_home
    user_home=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
    
    if [[ -d "$user_home/.config/regolith3" ]]; then
        return 0
    fi

    # Check for regolith-sway-clamshell (the script that handles lid events)
    if command -v regolith-sway-clamshell &>/dev/null; then
        return 0
    fi

    # Check if regolith packages are installed
    if dpkg -l | grep -q "regolith-session"; then
        return 0
    fi

    return 1
}

has_lid_switch() {
    [[ -d /proc/acpi/button/lid ]]
}

# --- Laptop Lid Configuration Functions ---

configure_regolith_lid_hibernate() {
    local user_home
    local xresources_file
    local real_user="${SUDO_USER:-$USER}"
    
    user_home=$(getent passwd "$real_user" | cut -d: -f6)
    xresources_file="$user_home/.config/regolith3/Xresources"
    
    info "Configuring Regolith lid-close hibernate..."
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$xresources_file")"
    
    # Check if already configured
    if grep -q "wm.lidclose.action.power: HIBERNATE" "$xresources_file" 2>/dev/null && \
       grep -q "wm.lidclose.action.battery: HIBERNATE" "$xresources_file" 2>/dev/null; then
        info "Regolith Xresources already configured for hibernate"
        return 0
    fi
    
    # Create file if it doesn't exist
    if [[ ! -f "$xresources_file" ]]; then
        touch "$xresources_file"
    fi
    
    # Remove any existing lid close settings to avoid duplicates
    sed -i '/wm\.lidclose\.action\./d' "$xresources_file"
    
    # Append hibernate settings
    cat >> "$xresources_file" << 'EOF'

! Lid close actions - hibernate instead of lock/sleep
! Added by setup_hibernation.sh script
wm.lidclose.action.power: HIBERNATE
wm.lidclose.action.battery: HIBERNATE
EOF
    
    # Fix ownership (since we're running as root)
    chown "$real_user:$real_user" "$xresources_file"
    
    success "Configured Regolith Xresources for lid-close hibernate"
    return 0
}

configure_systemd_logind_lid() {
    info "Configuring systemd-logind for lid-close hibernate..."
    
    local logind_conf="/etc/systemd/logind.conf"
    local logind_conf_d="/etc/systemd/logind.conf.d"
    local custom_conf="$logind_conf_d/hibernate-on-lid.conf"
    
    # Use drop-in directory for cleaner configuration
    mkdir -p "$logind_conf_d"
    
    cat > "$custom_conf" << 'EOF'
# Hibernate on lid close
# Added by setup_hibernation.sh script
[Login]
HandleLidSwitch=hibernate
HandleLidSwitchExternalPower=hibernate
HandleLidSwitchDocked=ignore
EOF
    
    success "Created systemd-logind lid-close configuration"
    info "Note: This may be overridden by desktop environment settings"
}

configure_gnome_lid_hibernate() {
    local real_user="${SUDO_USER:-$USER}"
    
    info "Configuring GNOME power settings for lid-close hibernate..."
    
    # Run gsettings as the actual user, not root
    if command -v gsettings &>/dev/null; then
        su - "$real_user" -c "gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'hibernate'" 2>/dev/null || true
        su - "$real_user" -c "gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'hibernate'" 2>/dev/null || true
        success "Configured GNOME power settings for lid-close hibernate"
    else
        warning "gsettings not found, skipping GNOME configuration"
    fi
}

configure_polkit_hibernate() {
    info "Configuring polkit rules for passwordless hibernation..."
    
    local polkit_rules_dir="/etc/polkit-1/rules.d"
    local polkit_rule_file="$polkit_rules_dir/85-hibernate.rules"
    
    # Check if polkit rules directory exists
    if [[ ! -d "$polkit_rules_dir" ]]; then
        warning "Polkit rules directory not found, skipping polkit configuration"
        return 1
    fi
    
    # Check if already configured
    if [[ -f "$polkit_rule_file" ]]; then
        info "Polkit hibernate rule already exists"
        return 0
    fi
    
    cat > "$polkit_rule_file" << 'EOF'
// Allow users in the "users" group to hibernate without authentication
// Added by setup_hibernation.sh script
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.login1.hibernate" ||
        action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
        action.id == "org.freedesktop.login1.handle-hibernate-key" ||
        action.id == "org.freedesktop.login1.hibernate-ignore-inhibit") {
        if (subject.isInGroup("users")) {
            return polkit.Result.YES;
        }
    }
});
EOF
    
    success "Created polkit rule for passwordless hibernation"
    return 0
}

setup_laptop_lid_hibernate() {
    echo
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE} Laptop Lid-Close Configuration          ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo
    
    if ! is_laptop; then
        info "This system does not appear to be a laptop. Skipping lid configuration."
        return 0
    fi
    
    success "Laptop detected!"
    
    if ! has_lid_switch; then
        warning "No lid switch detected. Skipping lid configuration."
        return 0
    fi
    
    success "Lid switch detected!"
    
    echo
    read -p "Would you like to configure lid-close to hibernate? (Y/n): " lid_response
    if [[ "$lid_response" =~ ^([nN][oO]|[nN])$ ]]; then
        info "Skipping lid-close configuration."
        return 0
    fi
    
    echo
    
    # Configure polkit for passwordless hibernate (needed for lid-close)
    configure_polkit_hibernate
    
    # Configure systemd-logind as fallback
    configure_systemd_logind_lid
    
    # Configure GNOME settings (if applicable)
    configure_gnome_lid_hibernate
    
    # Configure Regolith if detected
    if is_regolith; then
        success "Regolith desktop detected!"
        configure_regolith_lid_hibernate
        echo
        info "Regolith uses its own lid-close handler (regolith-sway-clamshell)."
        info "The Xresources configuration will take effect after you log out and log back in."
    else
        info "No Regolith desktop detected. Using systemd-logind and GNOME settings."
    fi
    
    echo
    success "Lid-close hibernate configuration complete!"
}

# --- Script Start ---
clear
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE} Ubuntu Hibernation Setup Assistant      ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo
warning "This script will modify critical system files (/etc/default/grub)."
warning "A backup of your GRUB configuration will be created."
read -p "Do you wish to continue? (y/N): " response
if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    info "Operation cancelled by user."
    exit 0
fi
echo

# --- Pre-flight Checks ---

# 1. Check for root privileges
info "Checking for root privileges..."
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root. Please use 'sudo'."
fi
success "Running as root."

# 2. Check for Secure Boot
info "Checking for Secure Boot status..."
if command -v mokutil &> /dev/null && mokutil --sb-state | grep -q "enabled"; then
    error "Secure Boot is enabled. Hibernation is not compatible with Secure Boot on Ubuntu. Please disable it in your system's UEFI/BIOS settings before running this script again."
fi
success "Secure Boot is disabled or not detected."

# 3. Find and validate the swap partition
info "Detecting swap partition..."
# Use lsblk to find swap partitions, get their UUID and NAME
SWAP_PARTITIONS=$(lsblk -no NAME,FSTYPE,UUID | awk '$2=="swap" && $3!="" {print "/dev/"$1, $3}')

if [ -z "$SWAP_PARTITIONS" ]; then
    error "No active swap partition found. Please create and enable a swap partition first."
elif [ $(echo "$SWAP_PARTITIONS" | wc -l) -gt 1 ]; then
    warning "Multiple swap partitions found. Please select which one to use for hibernation:"
    select OPT in $(echo "$SWAP_PARTITIONS" | awk '{print $1}'); do
        if [ -n "$OPT" ]; then
            SWAP_DEVICE=$OPT
            SWAP_UUID=$(echo "$SWAP_PARTITIONS" | grep "$SWAP_DEVICE" | awk '{print $2}')
            break
        else
            error "Invalid selection."
        fi
    done
else
    SWAP_DEVICE=$(echo "$SWAP_PARTITIONS" | awk '{print $1}')
    SWAP_UUID=$(echo "$SWAP_PARTITIONS" | awk '{print $2}')
fi

success "Using swap partition: ${SWAP_DEVICE} with UUID: ${SWAP_UUID}"

# 4. Check swap size against RAM size
info "Validating swap partition size..."
# Get sizes in bytes for accurate comparison
RAM_SIZE_BYTES=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') * 1024 ))
SWAP_SIZE_BYTES=$(lsblk -b -no SIZE "$SWAP_DEVICE" | head -n 1)
RAM_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $RAM_SIZE_BYTES/1024/1024/1024}")
SWAP_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $SWAP_SIZE_BYTES/1024/1024/1024}")

info "RAM Detected: ${RAM_SIZE_GB} GB"
info "Swap Size: ${SWAP_SIZE_GB} GB"

if [ "$SWAP_SIZE_BYTES" -lt "$RAM_SIZE_BYTES" ]; then
    error "Swap partition size (${SWAP_SIZE_GB} GB) is smaller than your RAM size (${RAM_SIZE_GB} GB). Hibernation may fail. Please resize your swap partition to be at least as large as your RAM."
fi
success "Swap partition size is sufficient for hibernation."

# --- Configuration Steps ---

# 5. Configure GRUB
info "Configuring GRUB..."
GRUB_CONFIG_FILE="/etc/default/grub"
GRUB_BACKUP_FILE="/etc/default/grub.bak.$(date +%F-%T)"

info "Backing up current GRUB config to ${GRUB_BACKUP_FILE}..."
cp "$GRUB_CONFIG_FILE" "$GRUB_BACKUP_FILE"

CMDLINE_VAR="GRUB_CMDLINE_LINUX_DEFAULT"
RESUME_PARAM="resume=UUID=${SWAP_UUID}"

# Check if the line exists
if grep -q "^${CMDLINE_VAR}=" "$GRUB_CONFIG_FILE"; then
    # Clean up old parameters first to avoid conflicts
    info "Removing any old 'resume' or 'resume_offset' parameters..."
    sed -i -E 's/resume=[^" \t]+//' "$GRUB_CONFIG_FILE"
    sed -i -E 's/resume_offset=[^" \t]+//' "$GRUB_CONFIG_FILE"

    # Add the new, correct resume parameter
    info "Adding new 'resume' parameter to GRUB command line."
    sed -i "s/\(${CMDLINE_VAR}=\"[^\"]*\)/\1 ${RESUME_PARAM}/" "$GRUB_CONFIG_FILE"

    # Clean up potential double spaces
    sed -i "s/  / /g" "$GRUB_CONFIG_FILE"
else
    error "Could not find '${CMDLINE_VAR}' in ${GRUB_CONFIG_FILE}. Cannot configure automatically."
fi
success "GRUB configuration updated."
echo "New GRUB command line:"
grep "^${CMDLINE_VAR}" "$GRUB_CONFIG_FILE"
echo

# 6. Configure initramfs
info "Configuring initramfs..."
INITRAMFS_CONFIG_DIR="/etc/initramfs-tools/conf.d"
mkdir -p "$INITRAMFS_CONFIG_DIR"
INITRAMFS_CONFIG_FILE="${INITRAMFS_CONFIG_DIR}/resume"
echo "RESUME=UUID=${SWAP_UUID}" > "$INITRAMFS_CONFIG_FILE"
success "initramfs resume file created at ${INITRAMFS_CONFIG_FILE}."

# 7. Apply all changes
info "Applying all changes. This may take a moment..."
info "Updating GRUB..."
update-grub
info "Updating initramfs..."
update-initramfs -u -k all
success "All changes have been applied."

# 8. Configure laptop lid-close (if applicable)
setup_laptop_lid_hibernate

# --- Final Instructions ---
echo
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN} Hibernation Setup Complete!             ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo
info "A system reboot is required for these changes to take effect."
info "After rebooting, you can test hibernation by running:"
echo -e "  ${YELLOW}systemctl hibernate${NC}"
echo

if is_laptop && has_lid_switch; then
    info "Lid-close hibernate has been configured."
    if is_regolith; then
        info "For Regolith: Log out and log back in after reboot to apply lid settings."
    fi
    echo
fi

info "If you encounter any issues, your original GRUB configuration is backed up at:"
echo -e "  ${YELLOW}${GRUB_BACKUP_FILE}${NC}"
echo

read -p "Would you like to reboot now? (y/N): " reboot_response
if [[ "$reboot_response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    info "Rebooting in 5 seconds..."
    sleep 5
    reboot
else
    info "Please reboot your system manually to complete the setup."
fi

exit 0
