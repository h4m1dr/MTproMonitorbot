# MTPro Monitor Bot — Auto Installer

This project provides a full automated installer and manager for **MTPro Monitor Bot**,  
making it extremely easy to install, configure, run, and manage the bot on Linux servers.

---

## Features

- **Automatic installation** of the bot, prerequisites, dependencies, and PM2  
- **Live status bar** showing:
  - Prerequisites status  
  - MTProxy detection  
  - Bot token status  
- One-click installation/update from GitHub  
- PM2 process management (Start / Stop / Restart / Status)  
- Manual edit menu for `index.js`, `scripts/`, and `usage.json`  
- Full cleanup & removal menu  
- Zero full-system upgrades (safe for all VPS users)

---

## System Requirements

The installer uses minimal packages and **does not perform any system-wide upgrades**  
(no `apt upgrade`, no `dist-upgrade`).

Disk usage values below are **calculated from a real Ubuntu VPS**:

| Package | Disk Usage |
|--------|------------|
| curl | 0.5 MB |
| git | 21.2 MB |
| nodejs | 3.8 MB |
| npm | 2.9 MB |
| **Total base prerequisites** | **≈28.4 MB** |
| pm2 (npm global) | ≈34 MB |

Bot directory (`/opt/MTproMonitorbot`) typically uses **5–40 MB** after `npm install`.

---

## Installation

### 1. Clone the repository

```bash
cd /opt
sudo git clone https://github.com/h4m1dr/MTproMonitorbot.git
cd MTproMonitorbot
sudo chmod +x mtpromonitor.sh
sudo bash mtpromonitor.sh
````

---

## Menu Structure

### 🔷 Main Menu

* **Prerequisites Menu**
  Install/update required packages (minimal install)
* **Bot Menu**
  Install bot, set token, PM2 management, manual edit
* **Cleanup Menu**
  Remove bot files, pm2 process, or npm cache

---

## Prerequisites Menu

### 1. Install / Update base packages

Installs only necessary packages (git, curl, nodejs, npm).
Already-installed packages are skipped.
**Approx disk usage: ~28.4 MB**

### 2. Install / Update pm2

If pm2 already exists, the script asks for confirmation.
**Approx disk usage: ~34 MB**

---

## Bot Menu

### 1. Install / Update MTPro Monitor Bot

* Clone / pull from GitHub
* Run `npm install`
* Ask for bot token
* Set token automatically inside `bot/index.js`

### 2. Set / Change Bot Token

Updates the token inside the bot code.

### 3. Start Bot (PM2)

```
pm2 start bot/index.js --name mtpromonitorbot
```

### 4. Stop Bot (PM2)

```
pm2 delete mtpromonitorbot
```

### 5. Restart Bot (PM2)

```
pm2 restart mtpromonitorbot
```

### 6. PM2 Status

Shows complete pm2 process table.

### 7. Manual Edit

Allows editing:

* `bot/index.js`
* `scripts/`
* `data/usage.json`

---

## Cleanup Menu

* Remove bot pm2 process
* Remove `/opt/MTproMonitorbot` directory
* Clear npm cache

---

## Project Repository

GitHub:
[https://github.com/h4m1dr/MTproMonitorbot](https://github.com/h4m1dr/MTproMonitorbot)

---

## Important Notes

* Script only touches the directory:
  `/opt/MTproMonitorbot`
* No other `/opt/*` directories are modified.
* No full system upgrades are ever performed.
* All installations are minimal and isolated.

---

## Support

Open an issue if you need help, find bugs, or want new features.
