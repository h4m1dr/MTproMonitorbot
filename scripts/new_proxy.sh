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

# Call create_proxy.sh and capture its output
CREATE_SCRIPT="$SCRIPT_DIR/create_proxy.sh"
if [ ! -x "$CREATE_SCRIPT" ]; then
  echo "ERROR: create_proxy.sh is not executable or not found at $CREATE_SCRIPT" >&2
  exit 1
fi

CREATE_OUT=""
if [ "${1-}" != "" ]; then
  # Optional port argument
  CREATE_OUT="$("$CREATE_SCRIPT" "$1")"
else
  CREATE_OUT="$("$CREATE_SCRIPT")"
fi

# Parse SECRET, PORT, TG_LINK from create_proxy.sh output
SECRET="$(echo "$CREATE_OUT" | sed -n 's/^SECRET=//p' | head -n 1)"
PORT="$(echo "$CREATE_OUT" | sed -n 's/^PORT=//p' | head -n 1)"
TG_LINK="$(echo "$CREATE_OUT" | sed -n 's/^TG_LINK=//p' | head -n 1)"

if [ -z "$SECRET" ]; then
  echo "ERROR: SECRET is empty (create_proxy.sh output was: $CREATE_OUT)" >&2
  exit 1
fi

if [ -z "$PORT" ]; then
  echo "ERROR: PORT is empty (create_proxy.sh output was: $CREATE_OUT)" >&2
  exit 1
fi

if ! echo "$PORT" | grep -Eq '^[0-9]+$'; then
  echo "ERROR: PORT is not numeric: $PORT" >&2
  exit 1
fi

if [ -z "$TG_LINK" ]; then
  echo "ERROR: TG_LINK is empty (create_proxy.sh output was: $CREATE_OUT)" >&2
  exit 1
fi

# Generate ID and name
PROXY_ID="p$(date +%s)$RANDOM"
PROXY_NAME="proxy-$(date +%Y%m%d-%H%M%S)"

# Store: ID SECRET PORT NAME TG_LINK
echo "$PROXY_ID $SECRET $PORT $PROXY_NAME $TG_LINK" >> "$PROXY_DB_FILE"

# Print single line for bot
echo "$PROXY_ID $SECRET $PORT $PROXY_NAME $TG_LINK"
