#!/bin/bash
# scripts/create_proxy.sh
# Create a new MTProxy secret for the official C MTProxy installed by
# HirbodBehnam/MTProtoProxyInstaller, then restart MTProxy and output
# connection link information for callers (like the Telegram bot).
#
# This script must be run as root (because it edits /etc/systemd/system/MTProxy.service
# and /opt/MTProxy/objs/bin/mtconfig.conf).

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: Please run this script as root (sudo)." >&2
  exit 1
fi

MT_DIR="/opt/MTProxy/objs/bin"
SERVICE_FILE="/etc/systemd/system/MTProxy.service"
MTCFG="$MT_DIR/mtconfig.conf"

if [ ! -f "$MTCFG" ]; then
  echo "Error: mtconfig.conf not found at $MTCFG" >&2
  echo "Make sure you have installed MTProxy using MTProtoProxyOfficialInstall.sh" >&2
  exit 1
fi

cd "$MT_DIR"

# Load config variables: PORT, CPU_CORES, SECRET_ARY, TAG, CUSTOM_ARGS, TLS_DOMAIN,
# HAVE_NAT, PUBLIC_IP, PRIVATE_IP, etc. :contentReference[oaicite:3]{index=3}
# shellcheck source=/opt/MTProxy/objs/bin/mtconfig.conf
source "$MTCFG"

# ---------- resolve PORT ----------
if [ -z "${PORT:-}" ]; then
  PORT="443"
fi

# ---------- generate secret ----------
# If user passes a 32-char hex as first arg, use it; otherwise random.
NEW_SECRET=""
if [ $# -ge 1 ] && [[ "$1" =~ ^[0-9a-fA-F]{32}$ ]]; then
  NEW_SECRET="$(echo "$1" | tr 'A-F' 'a-f')"
else
  # same style as installer: 32 hex chars :contentReference[oaicite:4]{index=4}
  NEW_SECRET="$(hexdump -vn "16" -e ' /1 "%02x"' /dev/urandom)"
fi

# SECRET_ARY is an array of existing secrets; we append new one.
# Example format in mtconfig.conf:
# SECRET_ARY=(0000... 1111... 2222...) :contentReference[oaicite:5]{index=5}
SECRET_ARY+=( "$NEW_SECRET" )

# ---------- rebuild ExecStart arguments (same logic as GenerateService) ----------
# GenerateService in original script roughly does:
# ARGS_STR="-u nobody -H $PORT"
# for i in "${SECRET_ARY[@]}"; do ARGS_STR+=" -S $i"; done
# [tag]  : -P TAG
# [tls]  : -D TLS_DOMAIN
# [nat]  : --nat-info PRIVATE_IP:PUBLIC_IP
# [cores]: -M (CPU_CORES-1)
# plus: $CUSTOM_ARGS --aes-pwd proxy-secret proxy-multi.conf :contentReference[oaicite:6]{index=6}

ARGS_STR="-u nobody -H $PORT"

for i in "${SECRET_ARY[@]}"; do
  ARGS_STR+=" -S $i"
done

if [ -n "${TAG:-}" ]; then
  ARGS_STR+=" -P $TAG"
fi

if [ -n "${TLS_DOMAIN:-}" ]; then
  ARGS_STR+=" -D $TLS_DOMAIN"
fi

if [ "${HAVE_NAT:-n}" = "y" ]; then
  ARGS_STR+=" --nat-info $PRIVATE_IP:$PUBLIC_IP"
fi

if [ -z "${CPU_CORES:-}" ]; then
  CPU_CORES="$(nproc --all || echo 2)"
fi

NEW_CORE=$((CPU_CORES - 1))
if [ "$NEW_CORE" -lt 1 ]; then
  NEW_CORE=1
fi

ARGS_STR+=" -M $NEW_CORE ${CUSTOM_ARGS:-} --aes-pwd proxy-secret proxy-multi.conf"

SERVICE_STR="[Unit]
Description=MTProxy
After=network.target

[Service]
Type=simple
WorkingDirectory=$MT_DIR
ExecStart=$MT_DIR/mtproto-proxy $ARGS_STR
Restart=on-failure
StartLimitBurst=0

[Install]
WantedBy=multi-user.target"

# ---------- write systemd service ----------
echo "$SERVICE_STR" >"$SERVICE_FILE"

# ---------- restart service ----------
systemctl daemon-reload
systemctl restart MTProxy

# ---------- update mtconfig.conf SECRET_ARY line ----------
SECRET_ARY_STR="${SECRET_ARY[*]}"
# Replace line starting with SECRET_ARY=(...) with new array value
sed -i "s/^SECRET_ARY=.*/SECRET_ARY=(${SECRET_ARY_STR})/" "$MTCFG"

# ---------- build proxy link ----------
# For official script, show-connections builds links like:
#  - Without TLS: secret=dd<SECRET>
#  - With TLS   : secret=ee<SECRET><hex_domain>  (TLS_DOMAIN hex, lowercase) :contentReference[oaicite:7]{index=7}

PUBLIC_IP_EFFECTIVE="$PUBLIC_IP"
if [ -z "$PUBLIC_IP_EFFECTIVE" ] || [ "$PUBLIC_IP_EFFECTIVE" = "YOUR_IP" ]; then
  if command -v curl >/dev/null 2>&1; then
    PUBLIC_IP_EFFECTIVE="$(curl -sS https://api.ipify.org || echo "YOUR_IP")"
  fi
fi

if [ -n "${TLS_DOMAIN:-}" ]; then
  HEX_DOMAIN=$(printf "%s" "$TLS_DOMAIN" | xxd -pu | tr 'A-F' 'a-f')
  SECRET_PARAM="ee${NEW_SECRET}${HEX_DOMAIN}"
else
  SECRET_PARAM="dd${NEW_SECRET}"
fi

TG_LINK="tg://proxy?server=${PUBLIC_IP_EFFECTIVE}&port=${PORT}&secret=${SECRET_PARAM}"

# ---------- output for caller (Node.js bot) ----------
echo "SECRET=$NEW_SECRET"
echo "PORT=$PORT"
echo "TG_LINK=$TG_LINK"
