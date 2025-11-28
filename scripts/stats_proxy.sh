#!/bin/bash
# scripts/stats_proxy.sh
# Print statistics about stored proxies and mtproxy service.
#
# Output:
#   PROXY_COUNT=<n>
#   BY_PORT=port1:count1,port2:count2,...
#   MTPROXY_SERVICE=active|inactive|not_found
#   LISTENING_PORTS=22,443,...

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
PROXY_DB_FILE="$DATA_DIR/proxies.txt"

mkdir -p "$DATA_DIR"

PROXY_COUNT=0
BY_PORT=""

if [ -f "$PROXY_DB_FILE" ] && grep -q '.' "$PROXY_DB_FILE"; then
  PROXY_COUNT="$(wc -l < "$PROXY_DB_FILE" | tr -d ' ')"

  # Extract per-port counts (3rd field = PORT)
  BY_PORT="$(
    awk '{print $3}' "$PROXY_DB_FILE" \
      | sort \
      | uniq -c \
      | awk '{print $2 ":" $1}' \
      | paste -sd',' - \
      || true
  )"
fi

echo "PROXY_COUNT=$PROXY_COUNT"
echo "BY_PORT=$BY_PORT"

# Check mtproxy systemd service status
SERVICE_STATUS="not_found"
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q '^mtproxy\.service'; then
    if systemctl is-active --quiet mtproxy; then
      SERVICE_STATUS="active"
    else
      SERVICE_STATUS="inactive"
    fi
  fi
fi

echo "MTPROXY_SERVICE=$SERVICE_STATUS"

# Collect listening TCP ports
LISTENING_PORTS=""
if command -v ss >/dev/null 2>&1; then
  LISTENING_PORTS="$(
    ss -tulnp 2>/dev/null \
      | awk 'NR>1 {print $5}' \
      | sed 's/.*://g' \
      | grep -E '^[0-9]+$' \
      | sort -n \
      | uniq \
      | paste -sd',' - \
      || true
  )"
fi

echo "LISTENING_PORTS=$LISTENING_PORTS"
