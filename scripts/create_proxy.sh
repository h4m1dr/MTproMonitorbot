#!/bin/bash
# scripts/create_proxy.sh
# Add a new MTProto secret to official C MTProxy (Hirbod MTProtoProxyInstaller)
# and print connection info for callers (bot, etc.).
# Output:
#   SECRET=<hex_secret>
#   PORT=<port>
#   TG_LINK=<tg://proxy?...>

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: please run this script as root (sudo)." >&2
  exit 1
fi

MT_DIR="/opt/MTProxy/objs/bin"
SERVICE_FILE="/etc/systemd/system/MTProxy.service"
MTCFG="$MT_DIR/mtconfig.conf"

if [ ! -d "$MT_DIR" ] || [ ! -f "$MTCFG" ]; then
  echo "Error: MTProxy does not seem to be installed via Hirbod's installer." >&2
  echo "Expected directory: $MT_DIR" >&2
  echo "Expected config   : $MTCFG" >&2
  exit 1
fi

if [ ! -f "$SERVICE_FILE" ]; then
  echo "Error: $SERVICE_FILE not found. Did you finish the installation?" >&2
  exit 1
fi

# Load current MTProxy config (PORT, CPU_CORES, SECRET_ARY, TAG, CUSTOM_ARGS, TLS_DOMAIN, HAVE_NAT, PUBLIC_IP, PRIVATE_IP)
# shellcheck disable=SC1090
source "$MTCFG"

# Function copied from HirbodBehnam/MTProtoProxyInstaller (GenerateService)
GenerateService() {
  local ARGS_STR
  ARGS_STR="-u nobody -H $PORT"

  # Add all secrets as -S <secret>
  for i in "${SECRET_ARY[@]}"; do
    ARGS_STR+=" -S $i"
  done

  # Optional advertising tag
  if [ -n "${TAG:-}" ]; then
    ARGS_STR+=" -P $TAG "
  fi

  # Optional Fake-TLS domain
  if [ -n "${TLS_DOMAIN:-}" ]; then
    ARGS_STR+=" -D $TLS_DOMAIN "
  fi

  # NAT info
  if [ "${HAVE_NAT:-n}" = "y" ]; then
    ARGS_STR+=" --nat-info $PRIVATE_IP:$PUBLIC_IP "
  fi

  # Worker count
  local NEW_CORE
  NEW_CORE=$((CPU_CORES - 1))
  ARGS_STR+=" -M $NEW_CORE ${CUSTOM_ARGS:-} --aes-pwd proxy-secret proxy-multi.conf"

  # Final systemd service unit
  read -r -d '' SERVICE_STR <<EOF || true
[Unit]
Description=MTProxy
After=network.target

[Service]
Type=simple
WorkingDirectory=$MT_DIR
ExecStart=$MT_DIR/mtproto-proxy $ARGS_STR
Restart=on-failure
StartLimitBurst=0

[Install]
WantedBy=multi-user.target
EOF
}

# Create a new random 32-hex secret
NEW_SECRET="$(hexdump -vn '16' -e ' /1 "%02x"' /dev/urandom)"
NEW_SECRET="${NEW_SECRET,,}"  # force lowercase

# Append to SECRET_ARY
SECRET_ARY+=("$NEW_SECRET")

# Rebuild systemd service file and restart MTProxy
GenerateService

cd /etc/systemd/system || exit 2
systemctl stop MTProxy || true
printf '%s\n' "$SERVICE_STR" > "$SERVICE_FILE"
systemctl daemon-reload
systemctl start MTProxy
systemctl is-active --quiet MTProxy || {
  echo "Warning: MTProxy service is not active after restart. Please check 'systemctl status MTProxy'." >&2
}

# Update mtconfig.conf SECRET_ARY line
cd "$MT_DIR" || exit 2
SECRET_ARY_STR="${SECRET_ARY[*]}"
# Replace existing SECRET_ARY assignment
sed -i "s/^SECRET_ARY=.*/SECRET_ARY=($SECRET_ARY_STR)/" "$MTCFG"

# Make sure we have PUBLIC_IP for link generation
if [ -z "${PUBLIC_IP:-}" ] || [ "$PUBLIC_IP" = "YOUR_IP" ]; then
  PUBLIC_IP="$(curl -fsS https://api.ipify.org || echo 'YOUR_IP')"
fi

# Build Telegram link (supports Fake-TLS)
SERVER_FIELD="$PUBLIC_IP"
# If you want to always use TLS_DOMAIN in server field, you can change this later.

if [ -n "${TLS_DOMAIN:-}" ]; then
  HEX_DOMAIN="$(printf '%s' "$TLS_DOMAIN" | xxd -pu | tr 'A-F' 'a-f')"
  SECRET_PARAM="ee${NEW_SECRET}${HEX_DOMAIN}"
else
  SECRET_PARAM="dd${NEW_SECRET}"
fi

TG_LINK="tg://proxy?server=${SERVER_FIELD}&port=${PORT}&secret=${SECRET_PARAM}"

echo "SECRET=$NEW_SECRET"
echo "PORT=$PORT"
echo "TG_LINK=$TG_LINK"
