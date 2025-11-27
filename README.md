# MTPro Monitor Bot
A fully automated MTProto monitoring & management bot with an interactive shell installer.

This project provides:

- A **Telegram bot** for managing MTProto proxies  
- A full **shell-based installation & management script** (`mtpromonitor.sh`)
- Menu-driven control system (Prerequisites / Bot Control / Cleanup)
- Auto-setup for:
  - Node.js, npm, Git, pm2
  - Bot installation & updates
  - Bot token injection
  - pm2 service control
  - Manual editing tools
- Optional integration with MTProxy stats (`http://127.0.0.1:8888/stats`)

---

# 🚀 Quick Start (Install From GitHub on Server)

Use on any Debian/Ubuntu server.

```bash
cd /opt
sudo git clone https://github.com/h4m1dr/MTproMonitorbot.git
cd MTproMonitorbot
sudo chmod +x mtpromonitor.sh
sudo ./mtpromonitor.sh
```

This launches the Main Menu where you can install prerequisites, install/update the bot, set the token, start/stop the bot, and clean up.

If the repo already exists, you can update it:

```bash
cd /opt/MTproMonitorbot
sudo git pull
sudo ./mtpromonitor.sh
```
📁 Installation Directory
Installer installs everything into:

```bash
/opt/MTproMonitorbot
```
Contents:
```
pgsql
/opt/MTproMonitorbot/
 ├── bot/              → Telegram bot logic (Node.js)
 ├── scripts/          → MTProxy management scripts (create/delete/list/stats)
 ├── data/             → Usage database (usage.json)
 ├── mtpromonitor.sh   → Installer & manager script
 └── node_modules/     → Installed node packages
```
pm2 process name used:
```
nginx
mtpromonitorbot
🧩 Prerequisites / Requirements
Supported OS: Debian / Ubuntu
```
Basic requirements:

Linux server

sudo/root access

curl, git, nodejs, npm (installer can install automatically)

pm2 (installer can install automatically)

Optional: Running MTProxy with stats (127.0.0.1:8888) for usage reporting

Installer can auto-install the following:

Package	Disk usage	Purpose
Node.js + npm	~250MB	Bot runtime
git	~50MB	Repo clone/update
curl	~10MB	Stats, downloads
pm2	~50MB	Bot service manager

📟 Status Header (Shown on Every Menu)
At top of the installer:
```
vbnet
Status: Prereqs=OK  Proxy=ON  BotToken=SET
```
Meaning:

Field	Meaning
Prereqs	Checks for node, npm, git
Proxy	Detects MTProxy stats or running process
BotToken	Shows if token is configured in bot/index.js

Values:

Prereqs: OK / MISSING

Proxy: ON / RUNNING(no stats) / OFF

BotToken: SET / NOT SET / NOT INSTALLED

🧭 Main Menu (Top-Level)
When you run:
```
./mtpromonitor.sh
```
You get:
```
Main Menu
[1] Prerequisites Menu
[2] Bot Menu
[3] Cleanup Menu
[0] Exit
1️⃣ Prerequisites Menu
```
```
Prerequisites Menu
[1] Show detailed system status
[2] Install / Update base packages (git, curl, nodejs, npm)
[3] Install / Update pm2
[0] Back to Main Menu
[1] Show system status
```
Displays:

Node.js + npm

git

pm2

MTProxy / stats

Bot installation directory

[2] Install base packages
Runs:
```
apt update
apt install -y git curl nodejs npm
```
[3] Install pm2
```
npm install -g pm2
```
2️⃣ Bot Menu
```
Bot Menu
[1] Install / Update MTPro Monitor Bot
[2] Set / Change Bot Token
[3] Start Bot (pm2)
[4] Stop Bot (pm2)
[5] Restart Bot (pm2)
[6] Show pm2 status
[7] Manual Edit (index.js, scripts, usage.json)
[0] Back to Main Menu
```
[1] Install / Update Bot
Creates install path

Clones or pulls latest GitHub version

Installs Node.js dependencies (npm install)

Prompts for bot token

Injects token into bot/index.js

Makes scripts executable

[2] Set / Change Bot Token
Updates token inside:
```
/opt/MTproMonitorbot/bot/index.js
```
[3] Start Bot
Runs:
```
pm2 start bot/index.js --name mtpromonitorbot
pm2 save
```
[4] Stop Bot
Runs:
```
pm2 delete mtpromonitorbot
```
[5] Restart Bot
```
pm2 restart mtpromonitorbot
```
[6] Show pm2 status
```
pm2 status
```
[7] Manual Edit
Allows editing:

bot/index.js

scripts/

data/usage.json

Using nano or default $EDITOR.

3️⃣ Cleanup Menu
```
Cleanup Menu
[1] Stop bot and remove pm2 process
[2] Remove bot install folder
[3] Clear npm cache
[0] Back to Main Menu
[1] Remove pm2 process
Stops and deletes pm2 service.
```
[2] Remove installation folder
Deletes:
```
/opt/MTproMonitorbot
```
[3] Clear npm cache
Runs:
```
npm cache clean --force
```
🔧 Manual File Overview
bot/index.js
Main Telegram bot logic.

scripts/
Shell scripts for MTProxy:

create_proxy.sh

delete_proxy.sh

list_proxies.sh

stats_proxy.sh

data/usage.json
Storage for traffic/usage info.

mtpromonitor.sh
Installer, updater, service manager.

🔄 Updating the Bot
On server:
```
cd /opt/MTproMonitorbot
sudo git pull
sudo ./mtpromonitor.sh
```
Choose:
```
[2] Bot Menu → [1] Install / Update Bot
```
🛑 Uninstall Completely
```
pm2 delete mtpromonitorbot
rm -rf /opt/MTproMonitorbot
```
✔️ Done
This README is clean, professional, and fully documents:

--Usage

--Installation

--Menus

--Maintenance

--File structure

--Requirements

