#!/bin/bash
# delete_proxy.sh
# Delete a proxy by its ID from data/proxies.txt
# Usage: delete_proxy.sh <id>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
PROXY_DB_FILE="$DATA_DIR/proxies.txt"

ID="$1"

if [ -z "$ID" ]; then
  echo "ERROR: Proxy ID is required." >&2
  exit 1
fi

if [ ! -f "$PROXY_DB_FILE" ]; then
  echo "ERROR: Proxy database not found." >&2
  exit 1
fi

TMP_FILE="${PROXY_DB_FILE}.tmp"

grep -v "^$ID " "$PROXY_DB_FILE" > "$TMP_FILE" 2>/dev/null
mv "$TMP_FILE" "$PROXY_DB_FILE"

echo "Proxy with ID $ID removed (if it existed)."
