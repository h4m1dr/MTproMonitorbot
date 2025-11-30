#!/bin/bash
# scripts/new_proxy.sh
# Create a new MTProto proxy entry by calling create_proxy.sh
# (which adds a secret to official MTProxy and restarts service),
# then store metadata in data/proxies.txt.
#
# Output format (single line):
#   ID SECRET PORT NAME TG_LINK

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
PROXY_DB_FILE="$DATA_DIR/proxies.txt"

mkdir -p "$DATA_DIR"

PORT_ARG=""
if [ $# -ge 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
  PORT_ARG="$1"
fi

CREATE_SCRIPT="$SCRIPT_DIR/create_proxy.sh"

if [ ! -x "$CREATE_SCRIPT" ]; then
  echo "ERROR: create_proxy.sh is not executable or missing at $CREATE_SCRIPT" >&2
  exit 1
fi

OUTPUT="$("$CREATE_SCRIPT" $PORT_ARG)"

SECRET=""
PORT=""
TG_LINK=""

while IFS= read -r line; do
  case "$line" in
    SECRET=*)
      SECRET="${line#SECRET=}"
      ;;
    PORT=*)
      PORT="${line#PORT=}"
      ;;
    TG_LINK=*)
      TG_LINK="${line#TG_LINK=}"
      ;;
  esac
done <<< "$OUTPUT"

if [ -z "$SECRET" ] || [ -z "$PORT" ] || [ -z "$TG_LINK" ]; then
  echo "ERROR: Failed to parse SECRET/PORT/TG_LINK from create_proxy.sh output." >&2
  echo "Raw output was:" >&2
  echo "$OUTPUT" >&2
  exit 1
fi

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

echo "$NEW_ID $SECRET $PORT $NAME $TG_LINK" >>"$PROXY_DB_FILE"

echo "$NEW_ID $SECRET $PORT $NAME $TG_LINK"
