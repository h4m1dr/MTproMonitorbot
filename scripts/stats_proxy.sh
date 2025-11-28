#!/bin/bash
# stats_proxy.sh
# Show simple stats about stored proxies and whether their ports are listening.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
PROXY_DB_FILE="$DATA_DIR/proxies.txt"

PROXY_STATS_URL="http://127.0.0.1:8888/stats"

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Return 0 if port is LISTENING, 1 otherwise
is_port_listening() {
  local PORT="$1"

  if has_cmd ss; then
    if ss -tuln 2>/dev/null | grep -q ":${PORT} " | grep -q "LISTEN"; then
      return 0
    fi
  elif has_cmd netstat; then
    if netstat -tuln 2>/dev/null | grep -q ":${PORT} " | grep -q "LISTEN"; then
      return 0
    fi
  fi

  return 1
}

count=0
if [ -f "$PROXY_DB_FILE" ]; then
  count=$(grep -c '.' "$PROXY_DB_FILE" 2>/dev/null)
fi

echo "Stored proxies: $count"

if [ "$count" -gt 0 ]; then
  echo ""
  echo "Per-proxy status (based on listening ports):"
  while read -r line; do
    [ -z "$line" ] && continue
    id=$(echo "$line" | awk '{print $1}')
    secret=$(echo "$line" | awk '{print $2}')
    port=$(echo "$line" | awk '{print $3}')
    name=$(echo "$line" | awk '{print $4}')

    [ -z "$name" ] && name="$id"

    if is_port_listening "$port"; then
      echo " - ${name} (port ${port}): UP"
    else
      echo " - ${name} (port ${port}): DOWN (no process listening on this port)"
    fi
  done < "$PROXY_DB_FILE"
fi

# Optional HTTP stats endpoint
if has_cmd curl; then
  if curl -s --max-time 1 "$PROXY_STATS_URL" >/dev/null 2>&1; then
    echo ""
    echo "Stats endpoint ($PROXY_STATS_URL):"
    curl -s --max-time 1 "$PROXY_STATS_URL"
  else
    echo ""
    echo "Stats endpoint ($PROXY_STATS_URL) is not reachable (not configured or proxy binary not running)."
  fi
fi
