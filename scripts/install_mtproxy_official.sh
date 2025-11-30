#!/bin/bash
# scripts/install_mtproxy_official.sh
# Wrapper around HirbodBehnam/MTProtoProxyInstaller (official C MTProxy).
# - Downloads MTProtoProxyOfficialInstall.sh if missing
# - Runs it (interactive)
# - Shows MTProxy systemd status

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root (for example: sudo bash scripts/install_mtproxy_official.sh)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== MTProxy official installer wrapper ==="
echo

# Ensure curl is available
if ! command -v curl >/dev/null 2>&1; then
  echo "[*] Installing curl (required to download installer)..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl
  else
    echo "Error: could not install curl (no apt-get/yum found)." >&2
    exit 1
  fi
fi

WORK_DIR="/opt/MTProtoProxyInstaller"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

if [ ! -f MTProtoProxyOfficialInstall.sh ]; then
  echo "[*] Downloading MTProtoProxyOfficialInstall.sh from GitHub (HirbodBehnam/MTProtoProxyInstaller)..."
  curl -fsSL -o MTProtoProxyOfficialInstall.sh \
    "https://raw.githubusercontent.com/HirbodBehnam/MTProtoProxyInstaller/master/MTProtoProxyOfficialInstall.sh"
  chmod +x MTProtoProxyOfficialInstall.sh
else
  echo "[*] Using existing MTProtoProxyOfficialInstall.sh in $WORK_DIR"
fi

echo
echo ">>> The next step is the ORIGINAL interactive installer."
echo ">>> Follow the prompts to choose port, secret, TAG, etc."
echo

bash MTProtoProxyOfficialInstall.sh

echo
echo "=== Post-install check ==="
if [ -f /etc/systemd/system/MTProxy.service ]; then
  echo "[*] MTProxy.service found."
  systemctl daemon-reload
  systemctl enable MTProxy || true
  systemctl restart MTProxy || true
  echo
  systemctl --no-pager --full status MTProxy || true
else
  echo "WARNING: /etc/systemd/system/MTProxy.service not found." >&2
  echo "Maybe the installer did not finish successfully." >&2
fi

echo
echo "Expected binary/config path: /opt/MTProxy/objs/bin"
if [ -d /opt/MTProxy/objs/bin ]; then
  ls -l /opt/MTProxy/objs/bin
else
  echo "Directory /opt/MTProxy/objs/bin does not exist."
fi

echo
echo "=== MTProxy official installation wrapper finished ==="
