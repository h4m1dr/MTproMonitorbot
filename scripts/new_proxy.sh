#!/bin/bash
# new_proxy.sh
# Create a new MTProto proxy entry with proper port selection logic.
# This script does NOT start any real proxy process by itself.
# It only selects a free port, generates a secret (if needed),
# stores proxy metadata in data/proxies.txt and prints "SECRET PORT NAME" to stdout.

# ===== Paths =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"
DEFAULT_PORT_FILE="$DATA_DIR/default_port"
PROXY_DB_FILE="$DATA_DIR/proxies.txt"

# ===== Helpers =====

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [--port <NUM|auto>] [--secret HEX] [--name NAME]

Options:
  --port NUM      Use this port if it is free. If it is in use, the script
                  will try to auto-select a free port and warn you.
  --port auto     Auto-select a free port. The script will first try the
                  default port (if configured) and then random ports in range.
  --secret HEX    Use this secret instead of generating a random one.
  --name NAME     Human-readable name for this proxy (no spaces recommended).

Behavior:
  - Default port is read from: $DEFAULT_PORT_FILE (fallback: 2033).
  - Port is ALWAYS checked for availability.
  - If no --port is given, the script will:
      1) Try the default port,
      2) If used, try random ports in [20000..40000] until a free one is found.
  - Proxy metadata is stored in: $PROXY_DB_FILE
    Each line: id secret port name
  - Script output to stdout (first line): SECRET PORT NAME
EOF
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

is_port_free() {
  local PORT="$1"

  if has_cmd ss; then
    if ss -tuln 2>/dev/null | grep -q ":${PORT} "; then
      return 1  # used
    fi
  elif has_cmd netstat; then
    if netstat -tuln 2>/dev/null | grep -q ":${PORT} "; then
      return 1  # used
    fi
  fi

  return 0  # free (or cannot detect → assume free)
}

find_free_port() {
  local DEFAULT_PORT="$1"
  local MIN_PORT=20000
  local MAX_PORT=40000
  local TRY_LIMIT=50

  if [ -n "$DEFAULT_PORT" ]; then
    if is_port_free "$DEFAULT_PORT"; then
      echo "$DEFAULT_PORT"
      return 0
    fi
  fi

  local i=0
  while [ "$i" -lt "$TRY_LIMIT" ]; do
    local PORT=$(( RANDOM % (MAX_PORT - MIN_PORT + 1) + MIN_PORT ))
    if is_port_free "$PORT"; then
      echo "$PORT"
      return 0
    fi
    i=$((i + 1))
  done

  echo ""
  return 1
}

generate_secret() {
  if has_cmd openssl; then
    openssl rand -hex 16 2>/dev/null
  else
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

generate_name() {
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  echo "proxy_${ts}"
}

# ===== Read default port =====
DEFAULT_PORT="2033"
if [ -f "$DEFAULT_PORT_FILE" ]; then
  RAW_PORT="$(tr -d ' \t\r\n' < "$DEFAULT_PORT_FILE" 2>/dev/null)"
  if echo "$RAW_PORT" | grep -Eq '^[0-9]+$'; then
    if [ "$RAW_PORT" -ge 1 ] && [ "$RAW_PORT" -le 65535 ]; then
      DEFAULT_PORT="$RAW_PORT"
    fi
  fi
fi

# ===== Parse arguments =====
PORT_ARG=""
SECRET_ARG=""
NAME_ARG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --port)
      shift
      if [ -z "$1" ]; then
        echo "ERROR: --port requires an argument." >&2
        print_usage
        exit 1
      fi
      PORT_ARG="$1"
      shift
      ;;
    --secret)
      shift
      if [ -z "$1" ]; then
        echo "ERROR: --secret requires an argument." >&2
        print_usage
        exit 1
      fi
      SECRET_ARG="$1"
      shift
      ;;
    --name)
      shift
      if [ -z "$1" ]; then
        echo "ERROR: --name requires an argument." >&2
        print_usage
        exit 1
      fi
      NAME_ARG="$1"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      print_usage
      exit 1
      ;;
  esac
done

CHOSEN_PORT=""

if [ -n "$PORT_ARG" ] && echo "$PORT_ARG" | grep -Eq '^[0-9]+$'; then
  if [ "$PORT_ARG" -lt 1 ] || [ "$PORT_ARG" -gt 65535 ]; then
    echo "ERROR: Port $PORT_ARG is out of range (1-65535)." >&2
    exit 1
  fi
  if is_port_free "$PORT_ARG"; then
    CHOSEN_PORT="$PORT_ARG"
  else
    echo "WARNING: Port $PORT_ARG is already in use. Trying to auto-select a free port..." >&2
    CHOSEN_PORT="$(find_free_port "$DEFAULT_PORT")"
    if [ -z "$CHOSEN_PORT" ]; then
      echo "ERROR: Could not find any free port in the auto range." >&2
      exit 1
    fi
  fi
elif [ "$PORT_ARG" = "auto" ] || [ "$PORT_ARG" = "AUTO" ]; then
  CHOSEN_PORT="$(find_free_port "$DEFAULT_PORT")"
  if [ -z "$CHOSEN_PORT" ]; then
    echo "ERROR: Could not find any free port in the auto range." >&2
    exit 1
  fi
else
  CHOSEN_PORT="$(find_free_port "$DEFAULT_PORT")"
  if [ -z "$CHOSEN_PORT" ]; then
    echo "ERROR: Could not find any free port in the auto range." >&2
    exit 1
  fi
fi

CHOSEN_SECRET="$SECRET_ARG"
if [ -z "$CHOSEN_SECRET" ]; then
  CHOSEN_SECRET="$(generate_secret)"
fi

CHOSEN_NAME="$NAME_ARG"
if [ -z "$CHOSEN_NAME" ]; then
  CHOSEN_NAME="$(generate_name)"
fi

mkdir -p "$DATA_DIR"
if [ ! -f "$PROXY_DB_FILE" ]; then
  touch "$PROXY_DB_FILE"
fi

PROXY_ID="p$(date +%s)$RANDOM"

echo "$PROXY_ID $CHOSEN_SECRET $CHOSEN_PORT $CHOSEN_NAME" >> "$PROXY_DB_FILE"

echo "$CHOSEN_SECRET $CHOSEN_PORT $CHOSEN_NAME"
