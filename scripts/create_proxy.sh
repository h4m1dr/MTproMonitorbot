#!/bin/bash
# scripts/create_proxy.sh
# Create new MTProto secret for mtproxy service and emit a tg:// link.
# Assumes mtproxy is installed (e.g. via MTProtoProxyInstaller) and
# reads secrets from /etc/mtproxy/secret.list.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
DEFAULT_PORT_FILE="$DATA_DIR/default_port"

mkdir -p "$DATA_DIR"

# Determine port: arg > default_port > 443
if [ $# -ge 1 ]; then
  PORT="$1"
elif [ -f "$DEFAULT_PORT_FILE" ]; then
  PORT="$(tr -d ' \n\r' < "$DEFAULT_PORT_FILE")"
else
  PORT="443"
fi

if ! echo "$PORT" | grep -Eq '^[0-9]+$'; then
  echo "ERROR: PORT is not numeric: $PORT" >&2
  exit 1
fi

if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
  echo "ERROR: PORT out of range: $PORT" >&2
  exit 1
fi

# Generate secret
if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is not installed." >&2
  exit 1
fi

SECRET="$(openssl rand -hex 16)"

# Append to mtproxy secret list
mkdir -p /etc/mtproxy
touch /etc/mtproxy/secret.list
echo "$SECRET" >> /etc/mtproxy/secret.list

# Restart mtproxy service if available
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart mtproxy >/dev/null 2>&1 || true
fi

# Discover public IP for link (best effort)
IP=""
if command -v curl >/dev/null 2>&1; then
  IP="$(curl -s --max-time 3 ifconfig.me || true)"
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

TG_LINK="tg://proxy?server=${IP}&port=${PORT}&secret=ee${SECRET}"

# Output for caller (key=value style)
echo "SECRET=$SECRET"
echo "PORT=$PORT"
echo "TG_LINK=$TG_LINK"
