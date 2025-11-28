#!/bin/bash
# scripts/delete_proxy.sh
# Delete a proxy by its ID:
#   1. Remove from data/proxies.txt
#   2. Remove its secret from /etc/mtproxy/secret.list
#   3. Restart mtproxy service (best effort)
#
# Usage:
#   delete_proxy.sh <PROXY_ID>
#
# Output:
#   DELETED <PROXY_ID>
#   NOT_FOUND <PROXY_ID>

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <PROXY_ID>" >&2
  exit 1
fi

TARGET_ID="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
PROXY_DB_FILE="$DATA_DIR/proxies.txt"

if [ ! -f "$PROXY_DB_FILE" ]; then
  echo "NOT_FOUND $TARGET_ID"
  exit 0
fi

LINE="$(grep -E "^${TARGET_ID} " "$PROXY_DB_FILE" || true)"

if [ -z "$LINE" ]; then
  echo "NOT_FOUND $TARGET_ID"
  exit 0
fi

SECRET="$(printf '%s\n' "$LINE" | awk '{print $2}')"

# Remove from proxies.txt
tmpfile="$(mktemp)"
grep -Ev "^${TARGET_ID} " "$PROXY_DB_FILE" > "$tmpfile" || true
mv "$tmpfile" "$PROXY_DB_FILE"

# Remove from /etc/mtproxy/secret.list
if [ -f /etc/mtproxy/secret.list ]; then
  tmpsec="$(mktemp)"
  grep -Ev "^${SECRET}\$" /etc/mtproxy/secret.list > "$tmpsec" || true
  mv "$tmpsec" /etc/mtproxy/secret.list
fi

# Restart mtproxy service (ignore failure)
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart mtproxy >/dev/null 2>&1 || true
fi

echo "DELETED $TARGET_ID"
