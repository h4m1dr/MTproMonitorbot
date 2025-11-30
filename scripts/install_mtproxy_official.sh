#!/bin/bash
# scripts/install_mtproxy_official.sh
# Install official C MTProxy using HirbodBehnam/MTProtoProxyInstaller.
# This script MUST be run as root on the server.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root (sudo bash scripts/install_mtproxy_official.sh)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== MTProxy Official Installer (Hirbod) Wrapper ==="
echo

# Ask basic options (you can hardcode defaults if you want)
read -r -p "Enter MTProxy port [443]: " PORT
PORT=${PORT:-443}

read -r -p "Enter TLS domain (fake TLS host, empty to disable): " TLS_DOMAIN
TLS_DOMAIN=${TLS_DOMAIN:-""}

echo
echo "Port      : $PORT"
echo "TLS domain: ${TLS_DOMAIN:-<none>}"
echo

read -r -p "Press ENTER to start installation using Hirbod script..." _

cd /opt || exit 2

# Download official installer script from Hirbod repo
# https://github.com/HirbodBehnam/MTProtoProxyInstaller :contentReference[oaicite:0]{index=0}
curl -o MTProtoProxyOfficialInstall.sh -L https://git.io/fjo3u

chmod +x MTProtoProxyOfficialInstall.sh

# Build argument list
ARGS=()
ARGS+=(--port "$PORT")
# We let installer generate secrets; later we add new secrets via our own script.
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
