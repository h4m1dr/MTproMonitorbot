# MTPro Monitor Bot — Auto Installer

**Version:** v0.3.1

This project provides a fully automated, menu-based installer and manager for **MTPro Monitor Bot** and **official C MTProxy** on Linux servers.  
It aims to make setup so simple that the user only runs **one script** and uses menus — no manual editing, no complex commands.

---

## 🔍 Overview

MTPro Monitor Bot Auto Installer:

- Installs and configures:
  - System prerequisites (git, curl, node, npm)
  - PM2 process manager
  - Official C MTProxy (via [MTProtoProxyInstaller](https://github.com/HirbodBehnam/MTProtoProxyInstaller))
  - MTPro Monitor Bot itself
- Provides a **unified interactive menu** to:
  - Install / update everything in one shot (*Full Install: MTProxy + Bot*)
  - Change ports, host/DNS, and MTProxy Fake-TLS domain
  - Start/stop/restart the bot with PM2
  - Clean up and remove files/processes safely
- Shows a **live status panel** at the top of every menu, including:
  - Installed prerequisites
  - MTProxy status (OFF / INSTALLED / RUNNING + port + TLS domain)
  - Bot token status (not installed / not set / masked token)
  - Public IP / DNS / default proxy port

The installer **never runs `apt upgrade` or `dist-upgrade`**. All changes are contained to the bot/MTProxy directories and required packages only. :contentReference[oaicite:1]{index=1}

---

## 💾 System Requirements & Disk Usage

The installer uses minimal packages and **does not perform any system-wide upgrades**.

Disk usage below is based on a real Ubuntu VPS (approximate):

| Component                | Disk Usage (approx.) |
|-------------------------|----------------------|
| `curl`                  | 0.5 MB               |
| `git`                   | 21.2 MB              |
| `nodejs`                | 3.8 MB               |
| `npm`                   | 2.9 MB               |
| **Base prerequisites**  | **≈ 28.4 MB**        |
| `pm2` (global via npm)  | ≈ 34 MB              |

The bot directory (`/opt/MTproMonitorbot`) typically uses **~5–40 MB** after `npm install`, depending on Node modules and logs. :contentReference[oaicite:2]{index=2}

---

## 🚀 Installation

> **Target directory:** `/opt/MTproMonitorbot`  
> The installer only touches this directory and the official MTProxy path `/opt/MTProxy`.

### 1. Clone the repository

```bash
cd /opt
sudo git clone https://github.com/h4m1dr/MTproMonitorbot.git
cd MTproMonitorbot
````

### 2. Run the installer

```bash
sudo bash mtpromonitor.sh
```

You **do not** need to run `chmod +x` manually.
The script’s own bootstrap (`auto_first_run_setup`) will mark helper scripts as executable on first run.

---

## 🧭 Main Menu

When you run `mtpromonitor.sh`, you’ll see the **Main Menu**:

* A big ASCII header

* A **status block** like:

  ```text
  Status:
    Prereqs : git curl node npm
    Proxy   : RUNNING (port=4949, tls=www.cloudflare.com)
    BotToken: 123456...9abc
  Net:
    IP         : 1.2.3.4
    DNS        : (not set)
    DefaultPort: 4949
  ```

* Then the main options:

```text
[1] Prerequisites Menu (install base packages, pm2, full install)
[2] Bot Menu (token, port, host/DNS, pm2 control, manual edit)
[3] MTProxy Menu (run official installer / advanced options)
[4] Cleanup Menu (stop, remove, clean cache)
[0] Exit
```

---

## ✅ Status Block Details

The **status block** is shown at the top of every menu:

* **Prereqs**

  * Shows which commands are actually installed: `git curl node npm`
  * If nothing is installed, it will show: `Prereqs : no`

* **Proxy**

  * States if MTProxy is:

    * `OFF`
    * `INSTALLED` (service exists but not running)
    * `RUNNING` (with port + TLS)
  * Reads configuration from:

    * `/opt/MTProxy/objs/bin/mtconfig.conf` (official installer)
    * `/etc/systemd/system/MTProxy.service` (systemd unit)
  * Example: `RUNNING (port=4949, tls=www.cloudflare.com)`

* **BotToken**

  * `NOT INSTALLED` — bot folder not present
  * `NOT SET` — placeholder `TOKEN_HERE` still in `bot/index.js`
  * masked token when set, e.g. `123456...9abc`

* **Net**

  * `IP` — public IP or `publicHost` from config (if set)
  * `DNS` — custom DNS name configured for links (or `(not set)`)
  * `DefaultPort` — port used in generated proxy links (read from `data/default_port`)

---

## 🔧 Prerequisites Menu

From Main Menu, choose:

```text
[1] Prerequisites Menu
```

Here you get:

1. **Install / Update base packages (git, curl, nodejs, npm)**

   * Installs only the needed packages.
   * Already-installed packages are skipped.
   * Approx disk usage: **~28.4 MB**

2. **Install / Update pm2**

   * Installs or updates `pm2` globally via npm.
   * Approx disk usage: **~34 MB**

3. **Full Install: official MTProxy + MTPro Monitor Bot**

   * The **one-shot installer**:

     * Runs Hirbod’s official C MTProxy installer (MTProtoProxyInstaller)

       * You choose port, secret(s), TLS_DOMAIN, NAT etc.
     * Reads the chosen port from `mtconfig.conf`
     * Installs/updates MTPro Monitor Bot (pulls from this repo)
     * Syncs `data/default_port` with MTProxy’s PORT
   * On re-run:

     * Offers to **purge previous MTProxy + Bot install** and reinstall from scratch
       (stops service, removes `/opt/MTProxy`, resets `data/` etc.)

---

## 🤖 Bot Menu

From Main Menu:

```text
[2] Bot Menu (token, port, host/DNS, pm2 control, manual edit)
```

Options (simplified overview):

1. **Set / Change Bot Token**

   * Edits `bot/index.js` and sets `const TOKEN = "..."`
   * If a token already exists, you can choose to keep or replace it.

2. **Set / Change Default Proxy Port**

   * Synchronizes:

     * `data/default_port`
     * `PORT` in `/opt/MTProxy/objs/bin/mtconfig.conf`
     * `-H <port>` in `/etc/systemd/system/MTProxy.service`
   * Restarts `MTProxy.service` with the new port.

3. **Configure Host / DNS for proxy links**

   * Allows setting:

     * Public host / IP used in generated `tg://` links
     * Optional DNS name

4. **Start Bot (pm2)**

5. **Stop Bot (pm2)**

6. **Restart Bot (pm2)**

7. **Show pm2 status**

8. **Manual Edit**

   * Quickly open:

     * `bot/index.js`
     * scripts inside `scripts/`
     * `data/usage.json`

---

## 🧱 MTProxy Menu (Wrapper Around Hirbod’s Installer)

From Main Menu:

```text
[3] MTProxy Menu (run official installer / advanced options)
```

This menu is a **wrapper** around the original
[[MTProtoProxyInstaller](https://github.com/HirbodBehnam/MTProtoProxyInstaller)](https://github.com/HirbodBehnam/MTProtoProxyInstaller) by **Hirbod Behnam**.

* If MTProxy is not installed yet, you will be asked to first run **Full Install** from the Prerequisites Menu.
* When installed, entering this menu:

  * Shows the unified status header (like other menus)
  * Then **directly opens** Hirbod’s MTProxy installer/menu:

    * Show connection links
    * Change TAG
    * Add / revoke secrets
    * Change worker numbers
    * Change NAT settings
    * Change custom arguments
    * Generate firewall rules
    * Uninstall proxy
    * About
* When you exit that menu, you are returned back to the Main Menu via the wrapper.

> The core MTProxy installation logic is fully credited to **Hirbod Behnam** and his
> project [[MTProtoProxyInstaller](https://github.com/HirbodBehnam/MTProtoProxyInstaller)](https://github.com/HirbodBehnam/MTProtoProxyInstaller).
> This project only wraps it in an outer menu with additional integration features.

---

## 🧹 Cleanup Menu

From Main Menu:

```text
[4] Cleanup Menu (stop, remove, clean cache)
```

Allows you to:

* Stop and remove the bot’s PM2 process (`mtpromonitorbot`)
* Remove bot data under `/opt/MTproMonitorbot/data`
* Optionally remove `node_modules` for a clean reinstall
* Clear npm cache (safe, optional)

This menu **never touches other `/opt` projects** and does **not** uninstall MTProxy by itself
(MTProxy uninstall is exposed via the MTProxy Menu → Hirbod’s script).

---

## 📦 Repository

Project GitHub:

* **MTPro Monitor Bot Auto Installer**
  [https://github.com/h4m1dr/MTproMonitorbot](https://github.com/h4m1dr/MTproMonitorbot)

External projects used / wrapped:

* **MTProtoProxyInstaller** (official C MTProxy installer & manager)
  By **Hirbod Behnam**
  [https://github.com/HirbodBehnam/MTProtoProxyInstaller](https://github.com/HirbodBehnam/MTProtoProxyInstaller)
* **Telegram MTProxy (C implementation)**
  [https://github.com/TelegramMessenger/MTProxy](https://github.com/TelegramMessenger/MTProxy)

Other tools:

* **Node.js + npm** — JavaScript runtime & package manager
* **PM2** — Process manager for Node.js applications

All credits for MTProxy installation, management logic and configuration menu
go to **Hirbod Behnam**’s MTProtoProxyInstaller project.
This repository focuses on **wrapping** those capabilities with a Telegram bot installer,
status UI, and a single unified menu experience.

---

## 🆘 Support

If you:

* Find a bug
* Need help installing
* Have feature requests

…please open an issue on:

> [https://github.com/h4m1dr/MTproMonitorbot/issues](https://github.com/h4m1dr/MTproMonitorbot/issues)
