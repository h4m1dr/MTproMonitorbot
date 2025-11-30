#!/bin/bash
# scripts/new_proxy.sh
# Create a new MTProxy proxy entry by calling create_proxy.sh
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

# Optional: port as first argument (not actually needed with official script,
# but kept for compatibility; forwarded to create_proxy.sh if given).
PORT_ARG=""
if [ $# -ge 1 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
  PORT_ARG="$1"
fi

CREATE_SCRIPT="$SCRIPT_DIR/create_proxy.sh"

if [ ! -x "$CREATE_SCRIPT" ]; then
  echo "ERROR: create_proxy.sh is not executable or missing at $CREATE_SCRIPT" >&2
  exit 1
fi

# 1) Call create_proxy.sh (must be root, or script itself will fail)
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

# 2) Determine new ID (incremental)
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

# 3) Decide name (later you can change to hproxy 1 / zproxy 1, etc.)
NAME="proxy-$NEW_ID"

# 4) Append record to proxies.txt => ID SECRET PORT NAME TG_LINK
echo "$NEW_ID $SECRET $PORT $NAME $TG_LINK" >>"$PROXY_DB_FILE"

# 5) Print same line to stdout for the Node.js bot
echo "$NEW_ID $SECRET $PORT $NAME $TG_LINK"
