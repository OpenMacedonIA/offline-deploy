# WatermelonD Offline Deployment Kit

## Overview
This toolkit allows you to install **WatermelonD** and its web interface **TangerineUI** on air-gapped systems or machines with restricted internet access. It works by pre-downloading all necessary dependencies (Debian packages, Python wheels, AI models) and the repository itself onto a USB drive.

This is ideal for secure environments, industrial controllers, or remote IoT devices without reliable connectivity.

## Prerequisites
1.  **Host Machine (Online):** A Linux system with internet access to prepare the drive.
    *   **Required tools:** `git`, `python3`, `pip`, `wget`, `curl`.
2.  **Target Machine (Offline):** Debian 12 (Bookworm) or Debian 13 (Trixie).
3.  **USB Drive:** At least **16GB** of free space is recommended (High Speed USB 3.0+ preferred).
    *   **Format:** `exFAT` (recommended for compatibility) or `ext4`.

## Quick Start

### Phase 1: Preparation (Online)
Run the preparation script on your internet-connected machine to create the "Installation Media".

1.  **Plug in** your USB drive / External HDD.
2.  **Identify** where it is mounted (e.g., `/media/user/MY_USB` or `/mnt/usb`).
3.  **Run** the `prepare_drive.sh` script from the repository root:

```bash
# Ensure it is executable
chmod +x offline/prepare_drive.sh

# Run the wizzard
sudo ./offline/prepare_drive.sh
```

**Interactive Wizard Steps:**
*   **Mount Point:** Enter the full path to your USB drive (e.g., `/media/jdoe/KINGSTON`).
*   **Git Branch:** Choose `main` (Stable release) or `next` (Development/Testing).
*   **Target OS:** Select the Debian version of your target machine(s). You can download packages for both if needed.
*   **TangerineUI (Kiosk Mode):**
    *   **Yes:** Downloads Xorg, Openbox, Chromium, and UI dependencies. Good for devices with screens.
    *   **No:** Downloads only core system dependencies. Good for headless servers.
*   **Verification:** The script will list what will be downloaded. Confirm to proceed.

The script will meticulously download:
*   ✅ Apt Packages (`.deb` archives) for the selected architecture.
*   ✅ Python Libraries (`.whl` wheels) for offline pip installation.
*   ✅ AI Models (HuggingFace Grape/Lime models).
*   ✅ The full WatermelonD source code.
*   ✅ A persistent configuration file (`offline_config.env`).

### Phase 2: Installation (Offline)
Move to your target (air-gapped) machine.

1.  **Boot** the target machine (Debian).
2.  **Plug in** the prepared USB drive.
3.  **Mount** the drive:
    ```bash
    # Identify the device (e.g., /dev/sdb1)
    lsblk

    # Create mount point and mount
    sudo mkdir -p /mnt/installer
    sudo mount /dev/sdb1 /mnt/installer
    ```

4.  **Run** the offline installer:
    ```bash
    cd /mnt/installer
    sudo ./installer.sh
    ```

**What the Installer Does:**
1.  **Loads Config:** Reads your choices (`Installing UI?`, `Branch?`) from `offline_config.env`.
2.  **System Deps:** Installs `.deb` packages from the USB cache using `dpkg`.
3.  **Python Env:** Creates a virtual environment and installs `.whl` files without internet.
4.  **AI Setup:** Moves pre-downloaded models to the correct internal directories (`.gemini/antigravity/brain` etc).
5.  **Service Setup:** Configures Systemd services (`neo.service`).
6.  **Kiosk Setup (If selected):** Configures Auto-login, `.xinitrc`, and Openbox to launch TangerineUI on boot.

## Directory Structure on USB
After preparation, your USB drive will look like this:

```
/mnt/usb/
├── offline_config.env      # Remembers if you chose Kiosk mode, etc.
├── installer.sh            # The installation script
├── repo/                   # Cloned WatermelonD repository
├── debs/                   # Apt packages (sorted by Debian version)
│   ├── bookworm/
│   └── trixie/
├── wheels/                 # Python .whl packages
└── models/                 # Pre-downloaded AI models
```

## Troubleshooting
*   **"Unable to locate package":** Installing offline relies strictly on the `.deb` cache. If you added a new dependency to `requirements.txt` or `apt` list, you must re-run `prepare_drive.sh` to download it.
*   **Permission Denied:** Ensure your USB drive is mounted with `exec` permissions.
    *   *Fix:* `sudo mount -o remount,exec /mnt/installer`
*   **Python Version Mismatch:** The wheels are downloaded for the Python version of the **Host** machine running `prepare_drive`. Ensure your Host and Target use the same major Python version (e.g., 3.11).

