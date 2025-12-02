#!/bin/bash
# setup_pybot.sh
# One-shot installer/updater for Python MTProxy bot.
# - Creates venv
# - Installs python-telegram-bot
# - Creates systemd service for the bot

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"
SERVICE_NAME="mtprobot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "=== Python MTProxy bot setup ==="

if [ ! -d "$VENV_DIR" ]; then
  echo "[*] Creating virtualenv at $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

echo "[*] Installing Python dependencies..."
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install python-telegram-bot

if [ ! -f "$SCRIPT_DIR/pybot/__init__.py" ]; then
  echo "Error: pybot package not found. Make sure pybot/ exists." >&2
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/config.json" ]; then
  cat >&2 <<EOF
Error: config.json not found in project root.
Create config.json with your bot_token, owner_ids, service_name, etc.
EOF
  exit 1
fi

echo "[*] Writing systemd service to $SERVICE_FILE"

cat <<EOF | sudo tee "$SERVICE_FILE" >/dev/null
[Unit]
Description=MTProxy manager Telegram bot
After=network.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$VENV_DIR/bin/python -m pybot.bot
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "[*] Reloading systemd daemon..."
sudo systemctl daemon-reload
echo "[*] Enabling bot service on boot..."
sudo systemctl enable "$SERVICE_NAME"

echo "=== setup_pybot.sh finished ==="
echo "You can now manage the bot service from mtpromonitor.sh menu."
