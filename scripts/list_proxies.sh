#!/bin/bash
# scripts/list_proxies.sh
# List all stored proxies from data/proxies.txt
# Output format per line:
#   ID SECRET PORT NAME TG_LINK
# If there are no proxies, prints "NO_PROXIES".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
PROXY_DB_FILE="$DATA_DIR/proxies.txt"

if [ ! -f "$PROXY_DB_FILE" ]; then
  echo "NO_PROXIES"
  exit 0
fi

if ! grep -q '.' "$PROXY_DB_FILE"; then
  echo "NO_PROXIES"
  exit 0
fi

cat "$PROXY_DB_FILE"
