# Ubuntu Hibernation Enabler Script

This repository contains a shell script, `setup_hibernation.sh`, designed to automate the process of enabling hibernation on Ubuntu and its derivatives (like Linux Mint, Pop!_OS, etc.). It configures the system to use a dedicated swap partition for storing the contents of RAM when hibernating.

## Overview

Hibernation saves the current state of your system (open applications, files, etc.) to your disk and then completely powers off the computer. When you turn it back on, your session is restored exactly as you left it. This is particularly useful for saving battery on laptops without losing your work.

This script makes the setup process easier by performing the necessary system checks and configuration changes automatically.

## ❗ DISCLAIMER ❗

This script modifies critical system files, specifically your GRUB (bootloader) configuration. While it includes safety checks and automatically creates a backup of your GRUB settings, there is always a small risk of issues.

**Please back up your important data before proceeding.** The author is not responsible for any data loss or system damage.

---

## Prerequisites

Before you use this script, please ensure you meet the following requirements:

1.  **Ubuntu-based Distribution**: The script is designed for Ubuntu and its derivatives.
2.  **Root Access**: You must run the script with `sudo` privileges.
3.  **Secure Boot Disabled**: Hibernation is incompatible with Secure Boot on most Ubuntu systems. You must disable Secure Boot in your computer's UEFI/BIOS settings. The script will check for this and stop if it's enabled.
4.  **A Swap Partition**: You need an active swap partition (not a swap file).
5.  **Sufficient Swap Size**: The swap partition **must be at least as large as your system's RAM**. If you have 16 GB of RAM, your swap partition needs to be 16 GB or larger.

---

## Step 1: Preparing a Swap Partition

If you don't have a suitable swap partition, you'll need to create one. The easiest way is to use a graphical tool like **GParted** from a live USB. Alternatively, you can use command-line tools if you have unallocated space on your drive.

**Using Command-Line Tools (`fdisk`)**

1.  **Identify your disk**:
    Find the name of the disk you want to add a partition to.
    ```bash
    sudo lsblk
    ```
    Your main drive is likely `/dev/sda` or `/dev/nvme0n1`.

2.  **Create a new partition**:
    Replace `/dev/sdX` with your disk name.
    ```bash
    sudo fdisk /dev/sdX
    ```
    Inside `fdisk`:
    -   Press `n` to create a new partition.
    -   Choose the partition type (primary is fine).
    -   Accept the default partition number and first sector.
    -   For the last sector, specify the size, e.g., `+16G` for 16 gigabytes.
    -   Press `t` to change the partition type.
    -   Enter `19` to select the "Linux swap" type.
    -   Press `w` to write the changes to the disk and exit.

3.  **Format and activate the swap partition**:
    Replace `/dev/sdXN` with the new partition's name (e.g., `/dev/sda3`).
    ```bash
    # Format the partition as swap space
    sudo mkswap /dev/sdXN

    # Turn on the swap partition
    sudo swapon /dev/sdXN
    ```

4.  **Make the swap partition permanent**:
    To ensure the system uses the swap partition after every reboot, add it to `/etc/fstab`.
    -   First, get the UUID of the new partition:
        ```bash
        sudo blkid /dev/sdXN
        ```
    -   Open `/etc/fstab` with a text editor:
        ```bash
        sudo nano /etc/fstab
        ```
    -   Add the following line at the end, replacing `YOUR_UUID_HERE` with the UUID you copied:
        ```
        UUID=YOUR_UUID_HERE none swap sw 0 0
        ```
    -   Save and close the file.

---

## Step 2: Using the Script

Once your swap partition is ready, you can run the setup script.

1.  **Clone or Download the Script**:
    ```bash
    git clone https://github.com/your-username/your-repo-name.git
    cd your-repo-name
    ```
    Alternatively, just download the `setup_hibernation.sh` file.

2.  **Make the Script Executable**:
    In the terminal, run the following command to give the script permission to execute:
    ```bash
    chmod +x setup_hibernation.sh
    ```

3.  **Run the Script**:
    Execute the script with `sudo`:
    ```bash
    sudo ./setup_hibernation.sh
    ```
    The script will guide you through the process, performing checks and asking for confirmation before making changes.

---

## Step 3: Testing Hibernation

After the script finishes, it will prompt you to reboot. A reboot is necessary for the changes to take effect.

1.  **Reboot your computer.**
2.  Once you've logged back in, open a few applications.
3.  Open a terminal and run the test command:
    ```bash
    sudo systemctl hibernate
    ```
    Your computer should save its state and power off completely.
4.  Turn your computer back on. It should boot up and restore your session exactly as you left it.

---

## Troubleshooting

-   **System Wakes Immediately After Hibernating**: This can be caused by various issues, often related to hardware drivers (especially NVIDIA) or kernel versions. Searching online for your specific hardware and Ubuntu version may provide a solution.
-   **How to Undo Changes**: The script creates a backup of your GRUB configuration in `/etc/default/` with a timestamp, like `grub.bak.2025-08-26-12:34:56`. To revert the changes, you can restore this file:
    ```bash
    # Move the modified file
    sudo mv /etc/default/grub /etc/default/grub.modified

    # Restore the backup (use the actual backup filename)
    sudo mv /etc/default/grub.bak.YYYY-MM-DD-HH:MM:SS /etc/default/grub

    # Update GRUB again
    sudo update-grub
    ```
    You should also delete the `resume` file created by the script:
    ```bash
    sudo rm /etc/initramfs-tools/conf.d/resume
    sudo update-initramfs -u -k all
    ```
    Then reboot.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
