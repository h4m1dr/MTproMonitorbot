#!/bin/bash
# scripts/install_mtproxy_official.sh
# Install official C MTProxy using HirbodBehnam/MTProtoProxyInstaller.
# This script MUST be run as root (sudo).

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root (sudo bash scripts/install_mtproxy_official.sh)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== MTProxy Official Installer (Hirbod) Wrapper ==="
echo

# Optional: read default port from data/default_port if exists
DEFAULT_PORT_FILE="$ROOT_DIR/data/default_port"
DEFAULT_PORT="443"
if [ -f "$DEFAULT_PORT_FILE" ]; then
  p=$(cat "$DEFAULT_PORT_FILE" 2>/dev/null || echo "")
  if echo "$p" | grep -Eq '^[0-9]+$'; then
    DEFAULT_PORT="$p"
  fi
fi

read -r -p "Enter MTProxy port [${DEFAULT_PORT}]: " PORT
PORT=${PORT:-$DEFAULT_PORT}

read -r -p "Enter TLS domain (fake TLS host, empty to disable): " TLS_DOMAIN
TLS_DOMAIN=${TLS_DOMAIN:-""}

echo
echo "Port      : $PORT"
echo "TLS domain: ${TLS_DOMAIN:-<none>}"
echo

read -r -p "Press ENTER to start installation using Hirbod script..." _

cd /opt || exit 2

# Download official installer script from Hirbod repo
curl -o MTProtoProxyOfficialInstall.sh -L https://git.io/fjo3u
chmod +x MTProtoProxyOfficialInstall.sh

ARGS=(--port "$PORT")
if [ -n "$TLS_DOMAIN" ]; then
  ARGS+=(--tls "$TLS_DOMAIN")
fi

echo
echo "Running: bash MTProtoProxyOfficialInstall.sh ${ARGS[*]}"
echo

bash MTProtoProxyOfficialInstall.sh "${ARGS[@]}"

echo
echo "If everything went fine, MTProxy service name should be: MTProxy"
echo "Service file: /etc/systemd/system/MTProxy.service"
echo "Config file : /opt/MTProxy/objs/bin/mtconfig.conf"
echo

systemctl status MTProxy --no-pager || true

echo
echo "=== MTProxy official installation finished ==="
