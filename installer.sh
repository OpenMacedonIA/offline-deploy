#!/bin/bash

# offline/installer.sh
# To be run on the TARGET machine from the USB drive.
# Installs WatermelonD using the offline assets.

set -e

# Defaults
DEST_DIR="/etc/watermelonD"
USB_MOUNT_POINT=$(dirname $(readlink -f "$0"))
FORCE_DEPS=false

# Load Config
if [ -f "$USB_MOUNT_POINT/offline_config.env" ]; then
    source "$USB_MOUNT_POINT/offline_config.env"
fi

# --- PARSE ARGS ---
while [[ $# -gt 0 ]]; do
  case $1 in
    -r|--root)
      DEST_DIR="$2"
      shift # past argument
      shift # past value
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

echo "========================================="
echo "===   WatermelonD Offline Installer   ==="
echo "========================================="
echo "Target: $DEST_DIR"
echo "Source: $USB_MOUNT_POINT"
echo ""
echo "WARNING: Installing to default: $DEST_DIR"
echo "Use -r <path> to specify a custom path."
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# 1. OS Detection (Debian Version)
if [ -f /etc/debian_version ]; then
    ver=$(cat /etc/debian_version)
    echo "Detected Debian Version: $ver"
    MAJOR_VER=$(echo $ver | cut -d. -f1)
    
    DEB_SOURCE_DIR=""
    if [ "$MAJOR_VER" -eq 12 ]; then
        DEB_SOURCE_DIR="$USB_MOUNT_POINT/dependencies/bookworm"
    elif [ "$MAJOR_VER" -eq 13 ] || [ "$MAJOR_VER" == "trixie" ]; then
        DEB_SOURCE_DIR="$USB_MOUNT_POINT/dependencies/trixie"
    else
        echo "Warning: Unknown Debian version. Attempting Bookworm packages as fallback..."
        DEB_SOURCE_DIR="$USB_MOUNT_POINT/dependencies/bookworm"
    fi
else
    echo "Error: Non-Debian system detected. Aborting."
    exit 1
fi

# 2. Install Dependencies (.deb)
echo "[1/5] Installing System Dependencies (Offline)..."
if [ -d "$DEB_SOURCE_DIR" ]; then
    sudo dpkg -i --force-depends "$DEB_SOURCE_DIR"/*.deb || true
    # Fix broken deps if possible (though we are offline, so apt-get -f install might fail if it needs net)
    # We rely on having all deps downloaded.
else
    echo "Error: Dependency directory $DEB_SOURCE_DIR not found!"
    exit 1
fi

# 3. Copy System Files
echo "[2/5] Copying System Files..."
sudo mkdir -p "$DEST_DIR"
sudo cp -r "$USB_MOUNT_POINT/source/WatermelonD/"* "$DEST_DIR/"
sudo chown -R $USER:$USER "$DEST_DIR"
cd "$DEST_DIR"

# 4. Setup Python Environment
echo "[3/5] Setting up Python 3.10..."

# Install PyEnv from offline cache
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

if [ ! -d "$PYENV_ROOT" ]; then
    cp -r "$USB_MOUNT_POINT/assets/pyenv" "$PYENV_ROOT"
fi

if ! grep -q 'export PYENV_ROOT="$HOME/.pyenv"' ~/.bashrc; then
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
    echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc
fi
eval "$(pyenv init -)"

# Install Python from offline tarball
# We need to use pyenv install but pointing to our caching... 
# Pyenv looks for cache in ~/.pyenv/cache
mkdir -p "$PYENV_ROOT/cache"
cp "$USB_MOUNT_POINT/assets/Python-3.10.13.tar.xz" "$PYENV_ROOT/cache/"

if ! pyenv versions | grep -q "3.10.13"; then
    echo "Compiling Python 3.10.13 (Offline)..."
    pyenv install 3.10.13
fi

# Create Venv
$PYENV_ROOT/versions/3.10.13/bin/python -m venv venv

# Install Wheels
echo "Installing Python Libraries..."
venv/bin/pip install --no-index --find-links="$USB_MOUNT_POINT/packages" -r requirements.txt

# 5. Restore Models & Configure
echo "[4/5] Restoring Models & Configuration..."
# Move models from USB structure to System structure
mkdir -p models
# Grape
if [ -d "$USB_MOUNT_POINT/models/grape" ]; then
    cp -r "$USB_MOUNT_POINT/models/grape/chardonnay" models/chardonnay
    cp -r "$USB_MOUNT_POINT/models/grape/malbec" models/malbec
    cp -r "$USB_MOUNT_POINT/models/grape/pinot" models/pinot
    cp -r "$USB_MOUNT_POINT/models/grape/grape-route" models/grape-route
fi
# Vosk
mkdir -p vosk-models/es
if [ -f "$USB_MOUNT_POINT/models/vosk/es/config.conf" ]; then # check a file inside
   cp -r "$USB_MOUNT_POINT/models/vosk/es"/* vosk-models/es/
else
   # Maybe we copied the folder 'es' itself
   cp -r "$USB_MOUNT_POINT/models/vosk/es" vosk-models/
fi

# Piper
mkdir -p piper/voices
cp "$USB_MOUNT_POINT/models/piper/"* piper/voices/

# Config & DB
mkdir -p logs config database docs/brain_memory
echo "{}" > config/config.json
export PYTHONPATH=$(pwd)
venv/bin/python database/init_db.py

# Systemd
echo "[5/5] Configuring Services..."
USER_NAME=$(whoami)
USER_ID=$(id -u)
USER_HOME=$HOME

mkdir -p "$USER_HOME/.config/systemd/user"

# Neo Service
cat <<EOT > "$USER_HOME/.config/systemd/user/neo.service"
[Unit]
Description=Neo Core Backend Service (WatermelonD)
After=network.target sound.target

[Service]
Type=simple
Environment=PYTHONUNBUFFERED=1
WorkingDirectory=$DEST_DIR
ExecStart=$DEST_DIR/venv/bin/python $DEST_DIR/NeoCore.py
Restart=always
RestartSec=5
SyslogIdentifier=watermelon_core

[Install]
WantedBy=default.target
EOT

# Enable
sudo loginctl enable-linger $USER_NAME
systemctl --user daemon-reload
systemctl --user enable neo.service
systemctl --user restart neo.service

# --- CONFIGURACIÓN DE KIOSK (TangerineUI) ---
if [ "$INSTALL_GUI" == "yes" ]; then
    echo "Configuring Kiosk Mode..."
    
    # Auto-login tty1
    sudo mkdir -p "/etc/systemd/system/getty@tty1.service.d"
    sudo bash -c "cat <<EOT > /etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOT"

    # .bash_profile
    if ! grep -q "exec startx" ~/.bash_profile; then
        echo 'if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then exec startx; fi' >> ~/.bash_profile
    fi

    # .xinitrc
    cat <<EOT > ~/.xinitrc
#!/bin/bash
xset -dpms
xset s off
xset s noblank
openbox &
echo "Waiting for backend..."
while ! curl -s http://localhost:5000 > /dev/null; do sleep 2; done
CHROMIUM_BIN="chromium"
command -v chromium-browser &> /dev/null && CHROMIUM_BIN="chromium-browser"
while true; do
  \$CHROMIUM_BIN --kiosk --no-first-run --disable-infobars --disable-session-crashed-bubble --disable-restore-session-state http://localhost:5000
  sleep 2
done
EOT
    chmod +x ~/.xinitrc
fi

# Admin Auth
venv/bin/python resources/tools/password_helper.py --user admin --password admin

# Cleanup target
rm -f setup_distrobox.sh setup_repos.sh || true

echo ""
echo "✅ Offline Installation Complete!"
echo "System installed at: $DEST_DIR"
