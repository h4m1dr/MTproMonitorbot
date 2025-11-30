#!/bin/bash
# setup.sh
# Main setup script for your project.
# You run this on the server AFTER git pull, and it will:
#  - Ensure all scripts are executable
#  - Optionally install official MTProxy via Hirbod installer
#  - (later) can also install node modules / create systemd services.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== mtproxy-bot setup ==="
echo

# Detect sudo
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

# 1) Make shell scripts executable
echo "[*] Marking shell scripts as executable..."
if [ -d "scripts" ]; then
  $SUDO chmod +x scripts/*.sh || true
fi

if [ -f "mtpromonitor.sh" ]; then
  $SUDO chmod +x mtpromonitor.sh || true
fi

echo "[+] Script permissions set."
echo

# 2) Check if MTProxy service exists; if not, offer to install via Hirbod installer
MTP_SERVICE_EXISTS=0

if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q "^MTProxy.service"; then
    MTP_SERVICE_EXISTS=1
  fi
fi

if [ "$MTP_SERVICE_EXISTS" -eq 1 ]; then
  echo "[+] MTProxy.service already exists. Skipping installation."
else
  echo "[!] MTProxy.service not found."
  echo "    You can install official C MTProxy using Hirbod's installer from inside this project."
  echo

  read -r -p "Do you want to run scripts/install_mtproxy_official.sh now? [y/N]: " ANSW
  ANSW=${ANSW:-N}

  if [[ "$ANSW" =~ ^[Yy]$ ]]; then
    if [ ! -f "scripts/install_mtproxy_official.sh" ]; then
      echo "Error: scripts/install_mtproxy_official.sh not found." >&2
      exit 1
    fi

    echo
    echo "[*] Running MTProxy official installer wrapper..."
    $SUDO bash scripts/install_mtproxy_official.sh
  else
    echo "[*] Skipping MTProxy installation for now."
  fi
fi

echo
echo "=== setup.sh finished ==="
echo "Now you can:"
echo "  - Ensure your bot's TOKEN is set in the config/index.js (or env)"
echo "  - Start the bot using your existing start script (e.g. mtpromonitor.sh or node bot/index.js)"
echo
echo "Later phases (menus / owner / tags) will be added on top of this."
