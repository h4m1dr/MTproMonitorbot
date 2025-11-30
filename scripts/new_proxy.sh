#!/bin/bash
# scripts/new_proxy.sh
# Helper around create_proxy.sh.
# - Calls scripts/create_proxy.sh (must be run as root).
# - Stores metadata into data/proxies.txt
# - Prints a single line:
#     ID SECRET PORT NAME TG_LINK

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
PROXY_DB_FILE="$DATA_DIR/proxies.txt"
CREATE_SCRIPT="$SCRIPT_DIR/create_proxy.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: please run this script as root (sudo)." >&2
  exit 1
fi

if [ ! -x "$CREATE_SCRIPT" ]; then
  echo "Error: $CREATE_SCRIPT is not executable or not found." >&2
  exit 1
fi

mkdir -p "$DATA_DIR"

# Call create_proxy.sh and capture its output
CREATE_OUTPUT="$("$CREATE_SCRIPT")" || {
  echo "Error: create_proxy.sh failed." >&2
  exit 1
}

# Extract values from its KEY=VALUE lines
SECRET="$(echo "$CREATE_OUTPUT" | awk -F= '/^SECRET=/{print $2}' | tail -n1)"
PORT="$(echo "$CREATE_OUTPUT" | awk -F= '/^PORT=/{print $2}' | tail -n1)"
TG_LINK="$(echo "$CREATE_OUTPUT" | awk -F= '/^TG_LINK=/{sub(/^TG_LINK=/,""); print}' | tail -n1)"

if [ -z "$SECRET" ] || [ -z "$PORT" ] || [ -z "$TG_LINK" ]; then
  echo "Error: could not parse output from create_proxy.sh" >&2
  echo "$CREATE_OUTPUT" >&2
  exit 1
fi

# Determine next numeric ID
NEW_ID=1
if [ -f "$PROXY_DB_FILE" ]; then
  LAST_LINE="$(grep -v '^[[:space:]]*$' "$PROXY_DB_FILE" | tail -n 1 || true)"
  if [ -n "$LAST_LINE" ]; then
    LAST_ID="$(echo "$LAST_LINE" | awk '{print $1}')"
    if [[ "$LAST_ID" =~ ^[0-9]+$ ]]; then
      NEW_ID=$((LAST_ID + 1))
    fi
  fi
fi

NAME="proxy-$NEW_ID"

# Append to DB file
echo "$NEW_ID $SECRET $PORT $NAME $TG_LINK" >>"$PROXY_DB_FILE"

# Print single line for caller (bot)
echo "$NEW_ID $SECRET $PORT $NAME $TG_LINK"
