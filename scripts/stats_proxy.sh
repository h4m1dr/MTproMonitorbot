#!/bin/bash
# stats_proxy.sh
# Show simple stats about stored proxies.
# If PROXY_STATS_URL is reachable, also print its content.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
PROXY_DB_FILE="$DATA_DIR/proxies.txt"

# Keep this URL in sync with mtpromonitor.sh if needed
PROXY_STATS_URL="http://127.0.0.1:8888/stats"

count=0
if [ -f "$PROXY_DB_FILE" ]; then
  count=$(grep -c '.' "$PROXY_DB_FILE" 2>/dev/null)
fi

echo "Stored proxies: $count"

if command -v curl >/dev/null 2>&1; then
  if curl -s --max-time 1 "$PROXY_STATS_URL" >/dev/null 2>&1; then
    echo ""
    echo "Stats endpoint ($PROXY_STATS_URL):"
    curl -s --max-time 1 "$PROXY_STATS_URL"
  else
    echo ""
    echo "Stats endpoint ($PROXY_STATS_URL) is not reachable."
  fi
else
  echo ""
  echo "curl is not installed. Skipping HTTP stats."
fi
