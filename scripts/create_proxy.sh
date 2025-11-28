#!/bin/bash
# scripts/create_proxy.sh
# Create new MTProto secret for mtproxy service and emit a proxy link.
# Assumes mtproxy is installed and reads secrets from /etc/mtproxy/secret.list.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
DEFAULT_PORT_FILE="$DATA_DIR/default_port"

mkdir -p "$DATA_DIR"

# Determine port: arg > default_port > 443
PORT=""
if [ "${1-}" != "" ]; then
  PORT="$1"
elif [ -f "$DEFAULT_PORT_FILE" ]; then
  # Read first line and keep only digits
  PORT="$(head -n 1 "$DEFAULT_PORT_FILE" | tr -cd '0-9')"
fi

if [ -z "$PORT" ]; then
  PORT="443"
fi

# Basic numeric validation
if ! echo "$PORT" | grep -Eq '^[0-9]+$'; then
  echo "Error: PORT is not numeric: $PORT" >&2
  exit 1
fi
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo "Error: PORT out of range (1-65535): $PORT" >&2
  exit 1
fi

# Generate a random MTProto secret (32 hex chars = 16 bytes)
if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl not found. Please install openssl." >&2
  exit 1
fi

SECRET="$(openssl rand -hex 16)"

# Append secret to /etc/mtproxy/secret.list
SECRET_DIR="/etc/mtproxy"
SECRET_FILE="$SECRET_DIR/secret.list"

if [ "$(id -u)" -ne 0 ]; then
  # Use sudo when not running as root
  sudo mkdir -p "$SECRET_DIR"
  sudo touch "$SECRET_FILE"
  echo "$SECRET" | sudo tee -a "$SECRET_FILE" >/dev/null
else
  mkdir -p "$SECRET_DIR"
  touch "$SECRET_FILE"
  echo "$SECRET" >> "$SECRET_FILE"
fi

# Restart mtproxy service if available
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-units --type=service | grep -qiE 'mtproxy\.service|MTProxy\.service'; then
    sudo systemctl restart mtproxy.service 2>/dev/null \
      || sudo systemctl restart MTProxy.service 2>/dev/null \
      || true
  fi
fi

# Detect public IP (best-effort)
IP=""
if command -v curl >/dev/null 2>&1; then
  IP="$(curl -s --max-time 5 ifconfig.me || true)"
fi

if [ -z "$IP" ]; then
  # Fallback to first local IP
  if command -v hostname >/dev/null 2>&1; then
    IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
fi

if [ -z "$IP" ]; then
  IP="SERVER_IP"
fi

# IMPORTANT:
# We use the EXACT same SECRET value that we wrote into secret.list.
# No "ee" / "dd" prefix here, so mtproxy and Telegram agree on the secret.
#
# Use a t.me link so it works nicely on Telegram Desktop / Web / Mobile.
PROXY_LINK="https://t.me/proxy?server=${IP}&port=${PORT}&secret=${SECRET}"

# Output for caller (key=value style)
echo "SECRET=$SECRET"
echo "PORT=$PORT"
echo "TG_LINK=$PROXY_LINK"
