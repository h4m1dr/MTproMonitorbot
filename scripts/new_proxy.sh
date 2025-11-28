#!/bin/bash
# scripts/new_proxy.sh
# Create a new MTProto proxy entry and actually register the secret
# via create_proxy.sh. This script:
#   1. Calls create_proxy.sh (which appends to /etc/mtproxy/secret.list
#      and restarts mtproxy service)
#   2. Stores proxy metadata in data/proxies.txt
#   3. Prints: ID SECRET PORT NAME TG_LINK

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
PROXY_DB_FILE="$DATA_DIR/proxies.txt"

mkdir -p "$DATA_DIR"
touch "$PROXY_DB_FILE"

# Optional: port as first argument (otherwise create_proxy.sh uses default_port/443)
if [ $# -ge 1 ]; then
  CREATE_OUT="$("$SCRIPT_DIR/create_proxy.sh" "$1")"
else
  CREATE_OUT="$("$SCRIPT_DIR/create_proxy.sh")"
fi

# Parse key=value style output
SECRET="$(printf '%s\n' "$CREATE_OUT" | sed -n 's/^SECRET=\(.*\)$/\1/p')"
PORT="$(printf '%s\n' "$CREATE_OUT" | sed -n 's/^PORT=\(.*\)$/\1/p')"
TG_LINK="$(printf '%s\n' "$CREATE_OUT" | sed -n 's/^TG_LINK=\(.*\)$/\1/p')"

if [ -z "${SECRET:-}" ] || [ -z "${PORT:-}" ]; then
  echo "ERROR: create_proxy.sh did not return SECRET/PORT" >&2
  echo "Raw output was:" >&2
  printf '%s\n' "$CREATE_OUT" >&2
  exit 1
fi

if ! echo "$PORT" | grep -Eq '^[0-9]+$'; then
  echo "ERROR: PORT is not numeric: $PORT" >&2
  exit 1
fi

# Generate ID and name
PROXY_ID="p$(date +%s)$RANDOM"
PROXY_NAME="proxy-$(date +%Y%m%d-%H%M%S)"

# Store: ID SECRET PORT NAME TG_LINK
echo "$PROXY_ID $SECRET $PORT $PROXY_NAME $TG_LINK" >> "$PROXY_DB_FILE"

# Print single line for bot
echo "$PROXY_ID $SECRET $PORT $PROXY_NAME $TG_LINK"
