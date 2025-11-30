#!/bin/bash
# MTPro Monitor Bot installer & manager
# All comments are in English

# ===== Colors =====
RED='\e[91m'
GREEN='\e[92m'
YELLOW='\e[93m'
BLUE='\e[94m'
MAGENTA='\e[95m'
CYAN='\e[96m'
WHITE='\e[97m'
BOLD='\e[1m'
RESET='\e[0m'

# ===== Global paths =====
INSTALL_DIR="/opt/MTproMonitorbot"
SERVICE_NAME="mtpromonitorbot"
CONFIG_PATH="$INSTALL_DIR/data/config.json"

# ===== Proxy detection config =====
# Change these if your stats URL or process name is different
PROXY_STATS_URL="http://127.0.0.1:8888/stats"
PROXY_PROCESS_PATTERN="mtproto|mtproxy|mtprotoproxy|mtg|mtgproxy|mtproxy-go"

# ===== Helper: check if command exists =====
has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# ===== Helper: check if apt package is installed =====
is_pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# ===== Helper: check if TCP port is free =====
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

  return 0  # free (or cannot detect, assume free)
}

# ===== Auto first-run setup (replaces old setup.sh) =====
auto_first_run_setup() {
  # Detect script root directory (where mtpromonitor.sh is located)
  local ROOT_DIR
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Prepare sudo if not running as root
  local SUDO_CMD=""
  if [ "$EUID" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      SUDO_CMD="sudo"
    fi
  fi

  # Make helper shell scripts executable (scripts/*.sh + this script)
  if [ -d "$ROOT_DIR/scripts" ]; then
    $SUDO_CMD chmod +x "$ROOT_DIR"/scripts/*.sh 2>/dev/null || true
  fi

  # Make this file executable
  $SUDO_CMD chmod +x "$ROOT_DIR/$(basename "$0")" 2>/dev/null || true

  # NO auto-install, NO questions, NO MTProxy checks  
  # Everything related to installation happens ONLY inside Prerequisites Menu
}


# ===== Helper: find a free port (default first, then random range) =====
find_free_port() {
  local DEFAULT_PORT="$1"
  local MIN_PORT=20000
  local MAX_PORT=40000
  local TRY_LIMIT=50

  # 1) Try default port if provided
  if [ -n "$DEFAULT_PORT" ]; then
    if is_port_free "$DEFAULT_PORT"; then
      echo "$DEFAULT_PORT"
      return 0
    fi
  fi

  # 2) Try random ports in range
  local i=0
  while [ "$i" -lt "$TRY_LIMIT" ]; do
    local PORT=$(( RANDOM % (MAX_PORT - MIN_PORT + 1) + MIN_PORT ))
    if is_port_free "$PORT"; then
      echo "$PORT"
      return 0
    fi
    i=$((i + 1))
  done

  # 3) No free port found in attempts
  echo ""
  return 1
}

# ===== Detect public IP (for default host) =====
detect_public_ip() {
  local ip=""

  if has_cmd curl; then
    ip=$(curl -s https://ifconfig.me 2>/dev/null)
    if echo "$ip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "$ip"
      return 0
    fi
    ip=$(curl -s https://api.ipify.org 2>/dev/null)
    if echo "$ip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "$ip"
      return 0
    fi
  fi

  if has_cmd dig; then
    ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | tail -n1)
    if echo "$ip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "$ip"
      return 0
    fi
  fi

  echo ""
  return 1
}

# ===== Config helpers (config.json for host/DNS) =====

get_config_value() {
  local KEY="$1"
  if [ ! -f "$CONFIG_PATH" ]; then
    echo ""
    return 0
  fi
  # naive JSON field extraction: "key": "value"
  sed -n "s/.*\"$KEY\" *: *\"\([^\"]*\)\".*/\1/p" "$CONFIG_PATH" | head -n1
}

write_config_values() {
  local HOST="$1"
  local DNS="$2"
  local dir
  dir="$(dirname "$CONFIG_PATH")"
  mkdir -p "$dir"

  cat >"$CONFIG_PATH" <<EOF
{
  "publicHost": "$HOST",
  "dnsName": "$DNS"
}
EOF
}

# ===== Short status line under header =====
short_status_header() {
  # Prerequisites summary
  local prereq_status="OK"
  local missing=""
  for cmd in node npm git; do
    if ! has_cmd "$cmd"; then
      prereq_status="MISSING"
      missing="$missing $cmd"
    fi
  done

  # Proxy status (stats endpoint or process names)
  local proxy_status="UNKNOWN"
  if has_cmd curl && curl -s --max-time 1 "$PROXY_STATS_URL" >/dev/null 2>&1; then
    proxy_status="ON"
  elif pgrep -fi "$PROXY_PROCESS_PATTERN" >/dev/null 2>&1; then
    proxy_status="RUNNING(no stats)"
  else
    proxy_status="OFF"
  fi

  # Bot token status
  local token_status="NOT INSTALLED"
  if [ -f "$INSTALL_DIR/bot/index.js" ]; then
    if grep -q 'const TOKEN = "TOKEN_HERE"' "$INSTALL_DIR/bot/index.js" 2>/dev/null; then
      token_status="NOT SET"
    else
      token_status="SET"
    fi
  fi

  echo -e "${WHITE}${BOLD}Status:${RESET} Prereqs=${YELLOW}$prereq_status${RESET}  Proxy=${YELLOW}$proxy_status${RESET}  BotToken=${YELLOW}$token_status${RESET}"
  if [ "$prereq_status" = "MISSING" ] && [ -n "$missing" ]; then
    echo -e "${YELLOW}Missing:${RESET}$missing"
  fi
  echo ""
}

# ===== Install prerequisites via apt (Debian/Ubuntu) =====
install_prereqs() {
  echo -e "${MAGENTA}${BOLD}Installing prerequisites (Debian/Ubuntu)...${RESET}"

  if ! has_cmd apt; then
    echo -e "${RED}apt not found. Please install Node.js, npm, git, curl manually.${RESET}"
    return
  fi

  if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This step requires root. Re-run script with sudo to auto-install packages.${RESET}"
    return
  fi

  local packages="git curl nodejs npm"
  local missing=""
  for pkg in $packages; do
    if ! is_pkg_installed "$pkg"; then
      missing="$missing $pkg"
    fi
  done

  if [ -z "$missing" ]; then
    echo -e "${GREEN}All base packages are already installed. Nothing to do.${RESET}"
    return
  fi

  echo -e "${YELLOW}The following packages will be installed:${RESET}$missing"
  echo -e "${YELLOW}Approximate total disk usage (if all are missing): ~28.4 MB on this VPS.${RESET}"
  echo ""

  apt update
  apt install -y $missing

  echo -e "${GREEN}Base prerequisites installation finished.${RESET}"
}

# ===== Install or update pm2 =====
install_pm2() {
  echo -e "${MAGENTA}${BOLD}Installing or updating pm2...${RESET}"

  if ! has_cmd npm; then
    echo -e "${RED}npm not found. Install Node.js + npm first.${RESET}"
    return
  fi

  if has_cmd pm2; then
    echo -ne "${YELLOW}pm2 is already installed. Reinstall / update it now? [y/N]: ${RESET}"
    read -r ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}Skipped pm2 installation/update.${RESET}"
      return
    fi
  fi

  echo -e "${YELLOW}Approximate disk usage for pm2: ~34 MB (global npm) on this VPS.${RESET}"
  npm install -g pm2
  echo -e "${GREEN}pm2 is installed/updated.${RESET}"
}

install_mtproxy_official_menu() {
  clear
  echo -e "${CYAN}${BOLD}MTPro Monitor Bot | MTProxy Install${RESET}"
  short_status_header
  echo -e "${MAGENTA}${BOLD}╭───────────────────────────────╮${RESET}"
  echo -e "${MAGENTA}${BOLD}│ ${WHITE}Install Official MTProxy${MAGENTA}       │${RESET}"
  echo -e "${MAGENTA}${BOLD}╰───────────────────────────────╯${RESET}"
  echo ""

  if [ ! -f "$INSTALL_DIR/scripts/install_mtproxy_official.sh" ]; then
    echo -e "${RED}scripts/install_mtproxy_official.sh not found in repo.${RESET}"
    echo -e "${YELLOW}Make sure you added it to your project and pushed to GitHub.${RESET}"
    read -r -p "Press Enter to return to Prerequisites Menu... " _
    return
  fi

  echo -e "${CYAN}This will run the official C MTProxy installer by Hirbod (MTProtoProxyInstaller).${RESET}"
  echo -e "${CYAN}You will be asked for port and (optional) TLS domain inside that script.${RESET}"
  echo ""
  read -r -p "Continue and run installer now? [y/N]: " ans
  ans=${ans:-N}
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled.${RESET}"
    sleep 1
    return
  fi

  sudo bash "$INSTALL_DIR/scripts/install_mtproxy_official.sh"
  echo -e "${GREEN}MTProxy installer finished (check systemctl status MTProxy).${RESET}"
  read -r -p "Press Enter to return to Prerequisites Menu... " _
}


# ===== Ask for bot token =====
ask_bot_token() {
  echo -ne "${CYAN}Enter your Telegram Bot Token: ${RESET}"
  read -r BOT_TOKEN
  if [ -z "$BOT_TOKEN" ]; then
    echo -e "${RED}Bot token cannot be empty.${RESET}"
    return 1
  fi
  BOT_TOKEN_VALUE="$BOT_TOKEN"
  return 0
}

# ===== Configure bot token inside bot/index.js =====
set_token_in_index() {
  local target_file="$INSTALL_DIR/bot/index.js"
  if [ ! -f "$target_file" ]; then
    echo -e "${RED}Cannot find $target_file to set token.${RESET}"
    return 1
  fi

  if grep -q 'const TOKEN = ' "$target_file"; then
    sed -i "s|const TOKEN = \".*\";|const TOKEN = \"$BOT_TOKEN_VALUE\";|" "$target_file"
    echo -e "${GREEN}Bot token has been written into bot/index.js${RESET}"
  else
    echo -e "${YELLOW}Could not find TOKEN constant in bot/index.js. Please update it manually.${RESET}"
    return 1
  fi
}

# ===== Set / Change default proxy port (with free-port check) =====
set_default_port_interactive() {
  local data_dir="$INSTALL_DIR/data"
  local default_port_file="$data_dir/default_port"
  local current_port="2033"

  if [ -f "$default_port_file" ]; then
    current_port=$(cat "$default_port_file" 2>/dev/null || echo "2033")
  fi

  while true; do
    echo ""
    echo -e "${CYAN}Default proxy port is used when creating new proxies (if scripts support it).${RESET}"
    echo -e "${CYAN}Current default port: ${WHITE}$current_port${RESET}"
    if is_port_free "$current_port"; then
      echo -e "${GREEN}Current port appears to be FREE.${RESET}"
    else
      echo -e "${YELLOW}Current port appears to be IN USE.${RESET}"
    fi

    echo -ne "${CYAN}Enter default proxy port [${current_port}] or type 'auto' to auto-select a free port: ${RESET}"
    read -r port_input

    if [ -z "$port_input" ]; then
      port_input="$current_port"
    fi

    if [[ "$port_input" =~ ^[Aa][Uu][Tt][Oo]$ ]]; then
      local new_port
      new_port=$(find_free_port "$current_port")
      if [ -z "$new_port" ]; then
        echo -e "${RED}Could not find any free port in the range. Try again.${RESET}"
        continue
      fi
      echo -e "${GREEN}Auto-selected free port: ${WHITE}$new_port${RESET}"
      mkdir -p "$data_dir"
      echo "$new_port" > "$default_port_file"
      echo -e "${GREEN}Default proxy port set to: ${WHITE}$new_port${RESET}"
      break
    fi

    if ! echo "$port_input" | grep -Eq '^[0-9]+$'; then
      echo -e "${RED}Invalid port. Please enter a number between 1 and 65535, or 'auto'.${RESET}"
      continue
    fi

    if [ "$port_input" -lt 1 ] || [ "$port_input" -gt 65535 ]; then
      echo -e "${RED}Port out of range. Please enter 1–65535.${RESET}"
      continue
    fi

    if ! is_port_free "$port_input"; then
      echo -ne "${YELLOW}Port ${WHITE}$port_input${YELLOW} is already in use.${RESET} "
      echo -e "${CYAN}You can try another port or type 'auto' to auto-select a free one.${RESET}"
      continue
    fi

    mkdir -p "$data_dir"
    echo "$port_input" > "$default_port_file"
    echo -e "${GREEN}Default proxy port set to: ${WHITE}$port_input${RESET}"
    break
  done
}

# ===== Configure Host / DNS (for proxy links) =====
configure_host_dns_interactive() {
  echo ""
  echo -e "${MAGENTA}${BOLD}Configure Host / DNS for proxy links${RESET}"

  local current_host
  local current_dns

  current_host="$(get_config_value "publicHost")"
  current_dns="$(get_config_value "dnsName")"

  # If no host is set in config, try to detect public IP automatically
  local detected_ip=""
  if [ -z "$current_host" ]; then
    detected_ip="$(detect_public_ip)"
    if [ -n "$detected_ip" ]; then
      current_host="$detected_ip"
    fi
  fi

  local display_host="$current_host"
  local display_dns="$current_dns"
  [ -z "$display_host" ] && display_host="(unknown)"
  [ -z "$display_dns" ] && display_dns="(not set)"

  echo -e "${CYAN}Detected / current public host/IP:${RESET} ${WHITE}$display_host${RESET}"
  echo -e "${CYAN}Current DNS / domain:${RESET}           ${WHITE}$display_dns${RESET}"
  echo ""

  # We do NOT ask for host/IP anymore, only DNS
  echo -ne "${CYAN}Enter DNS / domain (e.g. proxy.example.com) [${display_dns}]: ${RESET}"
  read -r new_dns
  if [ -z "$new_dns" ]; then
    new_dns="$current_dns"
  fi

  local final_host="$current_host"
  local final_dns="$new_dns"

  write_config_values "$final_host" "$final_dns"

  echo ""
  echo -e "${GREEN}Saved config:${RESET}"
  echo -e "  publicHost = ${WHITE}${final_host:-'(empty)'}${RESET}"
  echo -e "  dnsName    = ${WHITE}${final_dns:-'(empty)'}${RESET}"
}

# ===== Install & update MTPro Monitor Bot =====
install_or_update_bot() {
  echo -e "${MAGENTA}${BOLD}╭───────────────────────────────╮${RESET}"
  echo -e "${MAGENTA}${BOLD}│ ${WHITE}Install / Update Bot${MAGENTA}           │${RESET}"
  echo -e "${MAGENTA}${BOLD}╰───────────────────────────────╯${RESET}"

  if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${CYAN}Creating install directory: ${WHITE}$INSTALL_DIR${RESET}"
    sudo mkdir -p "$INSTALL_DIR" 2>/dev/null || mkdir -p "$INSTALL_DIR"
  fi

  if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "${CYAN}Repository found. Pulling latest changes...${RESET}"
    (cd "$INSTALL_DIR" && git pull)
  else
    echo -e "${CYAN}Cloning MTproMonitorbot repository into ${WHITE}$INSTALL_DIR${RESET}"
    git clone https://github.com/h4m1dr/MTproMonitorbot.git "$INSTALL_DIR"
  fi

  local target_file="$INSTALL_DIR/bot/index.js"
  local had_token_before="NO"
  if [ -f "$target_file" ]; then
    if grep -q 'const TOKEN = "' "$target_file"; then
      if ! grep -q 'const TOKEN = "TOKEN_HERE"' "$target_file"; then
        had_token_before="YES"
      fi
    fi
  fi

  echo -e "${CYAN}Running npm install...${RESET}"
  (cd "$INSTALL_DIR" && npm install)

  if [ "$had_token_before" = "YES" ]; then
    echo -e "${YELLOW}Existing bot token detected in bot/index.js.${RESET}"
    echo -ne "${CYAN}Keep current token? [Y/n]: ${RESET}"
    read -r ans
    if [[ "$ans" =~ ^[Nn]$ ]]; then
      if ask_bot_token; then
        set_token_in_index
      else
        echo -e "${YELLOW}Token was not changed. Keeping the existing one.${RESET}"
      fi
    else
      echo -e "${GREEN}Keeping existing bot token.${RESET}"
    fi
  else
    if ask_bot_token; then
      set_token_in_index
    else
      echo -e "${YELLOW}No token was set. You can set it later from Bot Menu (Set / Change Bot Token).${RESET}"
    fi
  fi

  set_default_port_interactive

  if [ -d "$INSTALL_DIR/scripts" ]; then
    chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null
  fi

  echo -e "${GREEN}Bot install/update process finished.${RESET}"
}

# ===== Start bot with pm2 =====
start_bot() {
  if ! has_cmd pm2; then
    echo -e "${RED}pm2 not found. Install pm2 from Prerequisites Menu first.${RESET}"
    return
  fi

  if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}Install dir $INSTALL_DIR not found. Install bot first.${RESET}"
    return
  fi

  echo -e "${CYAN}Starting bot with pm2...${RESET}"
  (cd "$INSTALL_DIR" && pm2 start bot/index.js --name "$SERVICE_NAME")
  pm2 save >/dev/null 2>&1
  echo -e "${GREEN}Bot is now managed by pm2 as: ${WHITE}$SERVICE_NAME${RESET}"
  echo -e "${YELLOW}To see logs: ${WHITE}pm2 logs $SERVICE_NAME${RESET}"
}

# ===== Stop bot with pm2 =====
stop_bot() {
  if ! has_cmd pm2; then
    echo -e "${RED}pm2 not found.${RESET}"
    return
  fi
  echo -e "${CYAN}Stopping pm2 process ${WHITE}$SERVICE_NAME${RESET}"
  pm2 delete "$SERVICE_NAME" >/dev/null 2>&1 || echo -e "${YELLOW}Process not found in pm2.${RESET}"
}

# ===== Restart bot with pm2 =====
restart_bot() {
  if ! has_cmd pm2; then
    echo -e "${RED}pm2 not found.${RESET}"
    return
  fi
  echo -e "${CYAN}Restarting pm2 process ${WHITE}$SERVICE_NAME${RESET}"
  pm2 restart "$SERVICE_NAME" >/dev/null 2>&1 || echo -e "${YELLOW}Process not found, try Start Bot first.${RESET}"
}

# ===== Show pm2 status =====
show_pm2_status() {
  if ! has_cmd pm2; then
    echo -e "${RED}pm2 not found.${RESET}"
    return
  fi
  echo -e "${CYAN}pm2 status:${RESET}"
  pm2 status
}

# ===== Manual edit menu (for power users) =====
manual_edit_menu() {
  while true; do
    clear
    echo -e "${CYAN}${BOLD}MTPro Monitor Bot | Manual Edit${RESET}"
    short_status_header
    echo -e "${MAGENTA}${BOLD}╭───────────────────────────────╮${RESET}"
    echo -e "${MAGENTA}${BOLD}│ ${WHITE}Manual Edit Menu${MAGENTA}              │${RESET}"
    echo -e "${MAGENTA}${BOLD}╰───────────────────────────────╯${RESET}"
    echo -e " ${CYAN}[1]${RESET} Edit bot/index.js (change token, commands, etc.)"
    echo -e " ${CYAN}[2]${RESET} Open scripts directory (shell)"
    echo -e " ${CYAN}[3]${RESET} Edit data/usage.json"
    echo -e " ${CYAN}[0]${RESET} Back to Bot Menu"
    echo ""
    echo -ne "${WHITE}Select an option: ${RESET}"
    read -r choice
    case "$choice" in
      1)
        if [ -f "$INSTALL_DIR/bot/index.js" ]; then
          ${EDITOR:-nano} "$INSTALL_DIR/bot/index.js"
        else
          echo -e "${RED}$INSTALL_DIR/bot/index.js not found.${RESET}"
          read -r -p "Press Enter to continue... " _
        fi
        ;;
      2)
        if [ -d "$INSTALL_DIR/scripts" ]; then
          echo -e "${YELLOW}Opening shell in scripts directory.${RESET}"
          read -r -p "Press Enter to continue... " _
          (cd "$INSTALL_DIR/scripts" && ${SHELL:-bash})
        else
          echo -e "${RED}$INSTALL_DIR/scripts directory not found.${RESET}"
          read -r -p "Press Enter to continue... " _
        fi
        ;;
      3)
        if [ -f "$INSTALL_DIR/data/usage.json" ]; then
          ${EDITOR:-nano} "$INSTALL_DIR/data/usage.json"
        else
          echo -e "${RED}$INSTALL_DIR/data/usage.json not found.${RESET}"
          read -r -p "Press Enter to continue... " _
        fi
        ;;
      0)
        break
        ;;
      *)
        echo -e "${RED}Invalid option.${RESET}"
        sleep 1
        ;;
    esac
  done
}

# ===== Prerequisites menu =====
prereq_menu() {
  while true; do
    clear
    echo -e "${CYAN}${BOLD}MTPro Monitor Bot | Prerequisites Menu${RESET}"
    short_status_header
    echo -e "${MAGENTA}${BOLD}╭───────────────────────────────╮${RESET}"
    echo -e "${MAGENTA}${BOLD}│ ${WHITE}Prerequisites Menu${MAGENTA}           │${RESET}"
    echo -e "${MAGENTA}${BOLD}╰───────────────────────────────╯${RESET}"
    echo -e " ${CYAN}[1]${RESET} Install / Update base packages (git, curl, nodejs, npm) ${YELLOW}(~28.4 MB disk on this VPS)${RESET}"
    echo -e " ${CYAN}[2]${RESET} Install / Update pm2 ${YELLOW}(~34 MB disk on this VPS)${RESET}"
    echo -e " ${CYAN}[3]${RESET} Install official MTProxy (Hirbod MTProtoProxyInstaller)"
    echo -e " ${CYAN}[4]${RESET} Install / Update MTPro Monitor Bot"
    echo -e " ${CYAN}[0]${RESET} Back to Main Menu"
    echo ""
    echo -ne "${WHITE}Select an option: ${RESET}"
    read -r choice
    case "$choice" in
      1)
        install_prereqs
        read -r -p "Press Enter to return to Prerequisites Menu... " _
        ;;
      2)
        install_pm2
        read -r -p "Press Enter to return to Prerequisites Menu... " _
        ;;
      3)
        install_mtproxy_official_menu
        ;;
      4)
        install_or_update_bot
        read -r -p "Press Enter to return to Prerequisites Menu... " _
        ;;
      0)
        break
        ;;
      *)
        echo -e "${RED}Invalid option.${RESET}"
        sleep 1
        ;;
    esac
  done
}



# ===== Bot menu =====
bot_menu() {
  while true; do
    clear
    echo -e "${CYAN}${BOLD}MTPro Monitor Bot | Bot Menu${RESET}"
    short_status_header
    echo -e "${MAGENTA}${BOLD}╭───────────────────────────────╮${RESET}"
    echo -e "${MAGENTA}${BOLD}│ ${WHITE}Bot Menu${MAGENTA}                     │${RESET}"
    echo -e "${MAGENTA}${BOLD}╰───────────────────────────────╯${RESET}"
    echo -e " ${CYAN}[1]${RESET} Set / Change Bot Token"
    echo -e " ${CYAN}[2]${RESET} Set / Change Default Proxy Port"
    echo -e " ${CYAN}[3]${RESET} Configure Host / DNS for proxy links"
    echo -e " ${CYAN}[4]${RESET} Start Bot (pm2)"
    echo -e " ${CYAN}[5]${RESET} Stop Bot (pm2)"
    echo -e " ${CYAN}[6]${RESET} Restart Bot (pm2)"
    echo -e " ${CYAN}[7]${RESET} Show pm2 status"
    echo -e " ${CYAN}[8]${RESET} Manual Edit (index.js, scripts, usage.json)"
    echo -e " ${CYAN}[0]${RESET} Back to Main Menu"
    echo ""
    echo -ne "${WHITE}Select an option: ${RESET}"
    read -r choice
    case "$choice" in
      1)
        # Token menu with warning if already set
        local_target_file="$INSTALL_DIR/bot/index.js"
        if [ -f "$local_target_file" ] && grep -q 'const TOKEN = "' "$local_target_file"; then
          if ! grep -q 'const TOKEN = "TOKEN_HERE"' "$local_target_file"; then
            echo -e "${YELLOW}Existing bot token detected in bot/index.js.${RESET}"
            echo -ne "${CYAN}Do you want to replace it? [y/N]: ${RESET}"
            read -r ans
            if [[ ! "$ans" =~ ^[Yy]$ ]]; then
              echo -e "${GREEN}Keeping current token.${RESET}"
              read -r -p "Press Enter to return to Bot Menu... " _
              continue
            fi
          fi
        fi
        if ask_bot_token; then
          set_token_in_index
        fi
        read -r -p "Press Enter to return to Bot Menu... " _
        ;;
      2)
        set_default_port_interactive
        read -r -p "Press Enter to return to Bot Menu... " _
        ;;
      3)
        configure_host_dns_interactive
        read -r -p "Press Enter to return to Bot Menu... " _
        ;;
      4)
        start_bot
        read -r -p "Press Enter to return to Bot Menu... " _
        ;;
      5)
        stop_bot
        read -r -p "Press Enter to return to Bot Menu... " _
        ;;
      6)
        restart_bot
        read -r -p "Press Enter to return to Bot Menu... " _
        ;;
      7)
        show_pm2_status
        read -r -p "Press Enter to return to Bot Menu... " _
        ;;
      8)
        manual_edit_menu
        ;;
      0)
        break
        ;;
      *)
        echo -e "${RED}Invalid option.${RESET}"
        sleep 1
        ;;
    esac
  done
}


# ===== Cleanup menu =====
cleanup_menu() {
  while true; do
    clear
    echo -e "${CYAN}${BOLD}MTPro Monitor Bot | Cleanup Menu${RESET}"
    short_status_header
    echo -e "${MAGENTA}${BOLD}╭───────────────────────────────╮${RESET}"
    echo -e "${MAGENTA}${BOLD}│ ${WHITE}Cleanup / Remove Menu${MAGENTA}       │${RESET}"
    echo -e "${MAGENTA}${BOLD}╰───────────────────────────────╯${RESET}"
    echo -e " ${CYAN}[1]${RESET} Stop bot and remove pm2 process"
    echo -e " ${CYAN}[2]${RESET} Remove bot install folder ($INSTALL_DIR)"
    echo -e " ${CYAN}[3]${RESET} Clear npm cache (optional cleanup)"
    echo -e " ${CYAN}[0]${RESET} Back to Main Menu"
    echo ""
    echo -ne "${WHITE}Select an option: ${RESET}"
    read -r choice
    case "$choice" in
      1)
        stop_bot
        read -r -p "Press Enter to return to Cleanup Menu... " _
        ;;
      2)
        echo -ne "${CYAN}Are you sure you want to remove ${WHITE}$INSTALL_DIR${CYAN}? [y/N]: ${RESET}"
        read -r ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
          sudo rm -rf "$INSTALL_DIR" 2>/dev/null || rm -rf "$INSTALL_DIR"
          echo -e "${GREEN}Removed ${WHITE}$INSTALL_DIR${RESET}"
        else
          echo -e "${YELLOW}Skip removing folder.${RESET}"
        fi
        read -r -p "Press Enter to return to Cleanup Menu... " _
        ;;
      3)
        if has_cmd npm; then
          echo -e "${CYAN}Clearing npm cache...${RESET}"
          npm cache clean --force
          echo -e "${GREEN}npm cache cleared.${RESET}"
        else
          echo -e "${RED}npm not found. Cannot clear cache.${RESET}"
        fi
        read -r -p "Press Enter to return to Cleanup Menu... " _
        ;;
      0)
        break
        ;;
      *)
        echo -e "${RED}Invalid option.${RESET}"
        sleep 1
        ;;
    esac
  done
}

# ===== Main menu =====
main_menu() {
  while true; do
    clear
    echo -e "${CYAN}${BOLD}"
    echo -e "███╗   ███╗████████╗██████╗ ██████╗  ██████╗ "
    echo -e "████╗ ████║╚══██╔══╝██╔══██╗██╔══██╗██╔════╝ "
    echo -e "██╔████╔██║   ██║   ██████╔╝██║  ██║██║  ███╗"
    echo -e "██║╚██╔╝██║   ██║   ██╔══██╗██║  ██║██║   ██║"
    echo -e "██║ ╚═╝ ██║   ██║   ██║  ██║██████╔╝╚██████╔╝"
    echo -e "╚═╝     ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═════╝  ╚═════╝ "
    echo -e "     ${WHITE}MTPro Monitor Bot${RESET}${CYAN} | ${WHITE}Auto Installer${RESET}"
    echo -e "${RESET}"
    short_status_header
    echo -e "${MAGENTA}${BOLD}╭───────────────────────────────╮${RESET}"
    echo -e "${MAGENTA}${BOLD}│ ${WHITE}Main Menu${MAGENTA}                     │${RESET}"
    echo -e "${MAGENTA}${BOLD}╰───────────────────────────────╯${RESET}"
    echo -e " ${CYAN}[1]${RESET} Prerequisites Menu (install base packages, pm2)"
    echo -e " ${CYAN}[2]${RESET} Bot Menu (install, token, port, host/DNS, pm2 control, manual edit)"
    echo -e " ${CYAN}[3]${RESET} Cleanup Menu (stop, remove, clean cache)"
    echo -e " ${CYAN}[0]${RESET} Exit"
    echo ""
    echo -ne "${WHITE}Select an option: ${RESET}"
    read -r choice
    case "$choice" in
      1)
        prereq_menu
        ;;
      2)
        bot_menu
        ;;
      3)
        cleanup_menu
        ;;
      0)
        echo -e "${GREEN}Bye.${RESET}"
        exit 0
        ;;
      *)
        echo -e "${RED}Invalid option.${RESET}"
        sleep 1
        ;;
    esac
  done
}

# ===== Start script =====
auto_first_run_setup
main_menu
