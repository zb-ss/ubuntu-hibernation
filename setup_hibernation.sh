#!/bin/bash

# ==============================================================================
# Ubuntu Hibernation Setup Script (Swap Partition Method)
# ==============================================================================
#
# This script automates the process of enabling hibernation on Ubuntu and its
# derivatives by configuring GRUB and initramfs to use a swap partition.
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

# --- Final Instructions ---
echo
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN} Hibernation Setup Complete!             ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo
info "A system reboot is required for these changes to take effect."
info "After rebooting, you can test hibernation by running:"
echo -e "  ${YELLOW}sudo systemctl hibernate${NC}"
echo
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
