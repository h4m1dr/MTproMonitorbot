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

# ===== Helper: check if command exists =====
has_cmd() {
  command -v "$1" >/dev/null 2>&1
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

  # Proxy status
  local proxy_status="UNKNOWN"
  if has_cmd curl && curl -s --max-time 1 http://127.0.0.1:8888/stats >/dev/null 2>&1; then
    proxy_status="ON"
  elif pgrep -f "mtproto" >/dev/null 2>&1 || pgrep -f "mtproxy" >/dev/null 2>&1; then
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

# ===== Detailed system status checker =====
check_status() {
  echo -e "${YELLOW}${BOLD}╭───────────────────────────────╮${RESET}"
  echo -e "${YELLOW}${BOLD}│ ${WHITE}System Status Check${YELLOW}            │${RESET}"
  echo -e "${YELLOW}${BOLD}╰───────────────────────────────╯${RESET}"

  # Node.js
  if has_cmd node; then
    node_ver=$(node -v 2>/dev/null)
    echo -e " ${WHITE}• Node.js:    ${GREEN}✓ Installed${RESET} ${CYAN}($node_ver)${RESET}  ${YELLOW}~250 MB disk${RESET}"
  else
    echo -e " ${WHITE}• Node.js:    ${RED}✗ Not Found${RESET}   ${YELLOW}~250 MB disk if installed${RESET}"
  fi

  # npm
  if has_cmd npm; then
    npm_ver=$(npm -v 2>/dev/null)
    echo -e " ${WHITE}• npm:        ${GREEN}✓ Installed${RESET} ${CYAN}($npm_ver)${RESET}"
  else
    echo -e " ${WHITE}• npm:        ${RED}✗ Not Found${RESET}"
  fi

  # git
  if has_cmd git; then
    echo -e " ${WHITE}• git:        ${GREEN}✓ Installed${RESET}  ${YELLOW}~50 MB disk${RESET}"
  else
    echo -e " ${WHITE}• git:        ${RED}✗ Not Found${RESET}  ${YELLOW}~50 MB disk if installed${RESET}"
  fi

  # pm2
  if has_cmd pm2; then
    echo -e " ${WHITE}• pm2:        ${GREEN}✓ Installed${RESET}  ${YELLOW}~50 MB disk${RESET}"
  else
    echo -e " ${WHITE}• pm2:        ${RED}✗ Not Found${RESET}  ${YELLOW}~50 MB disk if installed${RESET}"
  fi

  # MTProxy process (rough)
  if pgrep -f "mtproto" >/dev/null 2>&1 || pgrep -f "mtproxy" >/dev/null 2>&1; then
    echo -e " ${WHITE}• MTProxy:    ${GREEN}✓ Process detected${RESET}  ${YELLOW}~10–20 MB binary${RESET}"
  else
    echo -e " ${WHITE}• MTProxy:    ${RED}✗ Not detected${RESET}       ${YELLOW}(optional, but required for full stats)${RESET}"
  fi

  # Stats port check (default 8888)
  if has_cmd curl; then
    if curl -s --max-time 1 http://127.0.0.1:8888/stats >/dev/null 2>&1; then
      echo -e " ${WHITE}• Stats port: ${GREEN}✓ 127.0.0.1:8888 reachable${RESET}"
    else
      echo -e " ${WHITE}• Stats port: ${RED}✗ 127.0.0.1:8888 unavailable${RESET}"
    fi
  else
    echo -e " ${WHITE}• curl:       ${RED}✗ Not Found${RESET}  ${YELLOW}~10 MB if installed${RESET}"
  fi

  # Bot install dir
  if [ -d "$INSTALL_DIR" ]; then
    echo -e " ${WHITE}• Bot folder: ${GREEN}✓ $INSTALL_DIR${RESET}  ${YELLOW}~100 MB (code + node_modules)${RESET}"
  else
    echo -e " ${WHITE}• Bot folder: ${RED}✗ Not present${RESET} (planned: ${CYAN}$INSTALL_DIR${RESET})"
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

  apt update
  apt install -y git curl nodejs npm

  echo -e "${GREEN}Base prerequisites installation finished.${RESET}"
}

# ===== Install or update pm2 =====
install_pm2() {
  echo -e "${MAGENTA}${BOLD}Installing or updating pm2...${RESET}"
  if ! has_cmd npm; then
    echo -e "${RED}npm not found. Install Node.js + npm first.${RESET}"
    return
  fi

  npm install -g pm2
  echo -e "${GREEN}pm2 is installed/updated.${RESET}"
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

  # We assume the file contains: const TOKEN = "TOKEN_HERE";
  sed -i "s|const TOKEN = \"TOKEN_HERE\";|const TOKEN = \"$BOT_TOKEN_VALUE\";|" "$target_file"

  echo -e "${GREEN}Bot token has been written into bot/index.js${RESET}"
}

# ===== Install & update MTPro Monitor Bot =====
install_or_update_bot() {
  echo -e "${MAGENTA}${BOLD}╭───────────────────────────────╮${RESET}"
  echo -e "${MAGENTA}${BOLD}│ ${WHITE}Install / Update Bot${MAGENTA}           │${RESET}"
  echo -e "${MAGENTA}${BOLD}╰───────────────────────────────╯${RESET}"

  # Create install dir if missing
  if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${CYAN}Creating install directory: ${WHITE}$INSTALL_DIR${RESET}"
    sudo mkdir -p "$INSTALL_DIR" 2>/dev/null || mkdir -p "$INSTALL_DIR"
  fi

  # Clone or update repo
  if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "${CYAN}Repository found. Pulling latest changes...${RESET}"
    (cd "$INSTALL_DIR" && git pull)
  else
    echo -e "${CYAN}Cloning MTproMonitorbot repository into ${WHITE}$INSTALL_DIR${RESET}"
    git clone https://github.com/h4m1dr/MTproMonitorbot.git "$INSTALL_DIR"
  fi

  # npm install
  echo -e "${CYAN}Running npm install...${RESET}"
  (cd "$INSTALL_DIR" && npm install)

  # Ask for bot token
  if ask_bot_token; then
    set_token_in_index
  else
    echo -e "${YELLOW}No token was set. You can set it later from Bot Menu (Set / Change Bot Token).${RESET}"
  fi

  # Make scripts executable
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
    echo -e " ${CYAN}[1]${RESET} Install / Update base packages (git, curl, nodejs, npm)"
    echo -e " ${CYAN}[2]${RESET} Install / Update pm2"
    echo -e " ${CYAN}[0]${RESET} Back to Main Menu"
    echo ""
    echo -ne "${WHITE}Select an option: ${RESET}"
    read -r choice
    case "$choice" in
      1)
        install_prereqs
        ;;
      2)
        install_pm2
        ;;
      0)
        break
        ;;
      *)
        echo -e "${RED}Invalid option.${RESET}"
        ;;
    esac
    read -r -p "Press Enter to return to Prerequisites Menu... " _
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
    echo -e " ${CYAN}[1]${RESET} Install / Update MTPro Monitor Bot"
    echo -e " ${CYAN}[2]${RESET} Set / Change Bot Token"
    echo -e " ${CYAN}[3]${RESET} Start Bot (pm2)"
    echo -e " ${CYAN}[4]${RESET} Stop Bot (pm2)"
    echo -e " ${CYAN}[5]${RESET} Restart Bot (pm2)"
    echo -e " ${CYAN}[6]${RESET} Show pm2 status"
    echo -e " ${CYAN}[7]${RESET} Manual Edit (index.js, scripts, usage.json)"
    echo -e " ${CYAN}[0]${RESET} Back to Main Menu"
    echo ""
    echo -ne "${WHITE}Select an option: ${RESET}"
    read -r choice
    case "$choice" in
      1)
        install_or_update_bot
        ;;
      2)
        if ask_bot_token; then
          set_token_in_index
        fi
        ;;
      3)
        start_bot
        ;;
      4)
        stop_bot
        ;;
      5)
        restart_bot
        ;;
      6)
        show_pm2_status
        ;;
      7)
        manual_edit_menu
        ;;
      0)
        break
        ;;
      *)
        echo -e "${RED}Invalid option.${RESET}"
        ;;
    esac
    read -r -p "Press Enter to return to Bot Menu... " _
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
        ;;
      3)
        if has_cmd npm; then
          echo -e "${CYAN}Clearing npm cache...${RESET}"
          npm cache clean --force
          echo -e "${GREEN}npm cache cleared.${RESET}"
        else
          echo -e "${RED}npm not found. Cannot clear cache.${RESET}"
        fi
        ;;
      0)
        break
        ;;
      *)
        echo -e "${RED}Invalid option.${RESET}"
        ;;
    esac
    read -r -p "Press Enter to return to Cleanup Menu... " _
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
    echo -e " ${CYAN}[2]${RESET} Bot Menu (install, token, pm2 control, manual edit)"
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
main_menu
