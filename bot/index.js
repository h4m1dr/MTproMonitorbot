// bot/index.js
// MTPro Monitor Bot - Telegram interface

const fs = require("fs");
const path = require("path");
const { execFile } = require("child_process");
const TelegramBot = require("node-telegram-bot-api");

// This line is replaced by installer script (mtpromonitor.sh)
const TOKEN = "TOKEN_HERE";

if (!TOKEN || TOKEN === "TOKEN_HERE") {
  console.error("ERROR: Bot token is not set. Run the installer script first.");
  process.exit(1);
}

// Paths
const ROOT_DIR = path.join(__dirname, "..");
const DATA_DIR = path.join(ROOT_DIR, "data");
const SCRIPTS_DIR = path.join(ROOT_DIR, "scripts");
const CONFIG_PATH = path.join(DATA_DIR, "config.json");

// Default config values
const DEFAULT_CONFIG = {
  publicHost: "",
  dnsName: "",
  defaultPort: 2033 // default port if scripts do not return one
};

// Ensure data dir exists
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// ---- Config helpers ----
function loadConfig() {
  try {
    const raw = fs.readFileSync(CONFIG_PATH, "utf8");
    const cfg = JSON.parse(raw);
    return { ...DEFAULT_CONFIG, ...cfg };
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}

function saveConfig(cfg) {
  const merged = { ...DEFAULT_CONFIG, ...cfg };
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(merged, null, 2));
  return merged;
}

let config = loadConfig();

// ---- Shell helpers ----
function runScript(scriptName, args = [], callback) {
  const scriptPath = path.join(SCRIPTS_DIR, scriptName);
  execFile("bash", [scriptPath, ...args], (err, stdout, stderr) => {
    if (err) {
      console.error(`Script ${scriptName} failed:`, stderr || err.message);
      return callback(err, null);
    }
    callback(null, (stdout || "").trim());
  });
}

// Promise wrapper (for async/await)
function runScriptAsync(scriptName, args = []) {
  return new Promise((resolve, reject) => {
    runScript(scriptName, args, (err, out) => {
      if (err) return reject(err);
      resolve(out);
    });
  });
}

// Check if a TCP port is listening (ON/OFF) using "ss"
function checkPortStatus(port) {
  return new Promise((resolve) => {
    if (!port) return resolve("UNKNOWN");
    const cmd = `ss -tuln 2>/dev/null | grep -q ":${port} " && echo ON || echo OFF`;
    execFile("bash", ["-c", cmd], (err, stdout) => {
      if (err) return resolve("UNKNOWN");
      const out = (stdout || "").trim();
      if (out === "ON") return resolve("ONLINE");
      if (out === "OFF") return resolve("OFFLINE");
      return resolve("UNKNOWN");
    });
  });
}

// ---- Proxy helpers ----

// Parse a line of proxy info.
//
// We try to be robust with the format. Example supported formats:
//   "proxy_2025_01 9b1f2c... 2033"
//   "id1 proxy_2025_01 9b1f2c... 2033"
// Anything that looks like 32 hex chars is secret,
// anything that looks like a number 1-65535 is port,
// and the first token that is not secret/port is name.
function parseProxyLine(line, fallbackIndex) {
  const parts = line.split(/\s+/).filter(Boolean);
  let name = "";
  let secret = "";
  let port = "";
  let id = String(fallbackIndex);

  const hex32 = /^[0-9a-fA-F]{32}$/;
  const portRe = /^[0-9]{1,5}$/;

  for (const p of parts) {
    if (!secret && hex32.test(p)) {
      secret = p;
      continue;
    }
    if (!port && portRe.test(p)) {
      port = p;
      continue;
    }
  }

  // Collect name/id from remaining tokens
  const others = parts.filter((p) => p !== secret && p !== port);
  if (others.length > 0) {
    name = others[0];
    if (others.length > 1) {
      id = others[0]; // treat first token as id if present
    }
  } else {
    name = `proxy_${fallbackIndex + 1}`;
  }

  return { id, name, secret, port };
}

// Parse list_proxies script output into objects
function parseProxyList(output) {
  if (!output) return [];
  const lines = output
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !/^NO_PROXIES/i.test(l));

  return lines.map((line, idx) => parseProxyLine(line, idx));
}

// Build tg://proxy link using config (DNS > IP)
function buildProxyLink(secret, port) {
  const host = config.dnsName || config.publicHost || "YOUR_IP_HERE";
  if (!secret || !port) {
    return "tg://proxy?server=" + host;
  }
  return `tg://proxy?server=${host}&port=${port}&secret=${secret}`;
}

// ---- Telegram bot ----

const bot = new TelegramBot(TOKEN, { polling: true });

// Main menu keyboard (inline)
function mainMenuKeyboard() {
  return {
    reply_markup: {
      inline_keyboard: [
        [
          { text: "View all proxies", callback_data: "menu_list" },
          { text: "New proxy", callback_data: "menu_new" }
        ],
        [
          { text: "Status", callback_data: "menu_status" },
          { text: "Delete proxy", callback_data: "menu_delete" }
        ]
      ]
    }
  };
}

// Inline keyboard for list of proxies (connect buttons). 4 per row.
function buildProxyListKeyboard(proxies) {
  const rows = [];
  const buttons = proxies.map((p) => {
    const link = buildProxyLink(p.secret, p.port);
    return {
      text: `${p.name} (${p.port || "?"})`,
      url: link
    };
  });

  for (let i = 0; i < buttons.length; i += 4) {
    rows.push(buttons.slice(i, i + 4));
  }

  return { inline_keyboard: rows };
}

// Inline keyboard for delete menu (4 per row + back)
function buildDeleteKeyboard(proxies, page = 0, perPage = 8) {
  const start = page * perPage;
  const slice = proxies.slice(start, start + perPage);

  const rows = [];
  for (let i = 0; i < slice.length; i += 4) {
    const row = slice.slice(i, i + 4).map((p) => ({
      text: `${p.name} (${p.port || "?"})`,
      callback_data: `del_proxy:${p.id}`
    }));
    rows.push(row);
  }

  const totalPages = Math.max(1, Math.ceil(proxies.length / perPage));
  const navRow = [];
  if (page > 0) {
    navRow.push({ text: "⬅ Prev", callback_data: `del_page:${page - 1}` });
  }
  if (page < totalPages - 1) {
    navRow.push({ text: "Next ➡", callback_data: `del_page:${page + 1}` });
  }
  if (navRow.length > 0) rows.push(navRow);

  rows.push([{ text: "⬅ Back to main menu", callback_data: "back_main" }]);

  return { inline_keyboard: rows };
}

// ---- Telegram handlers ----

// /start → main menu
bot.onText(/\/start/, (msg) => {
  const chatId = msg.chat.id;
  bot.sendMessage(chatId, "Select an option:", mainMenuKeyboard());
});

// Legacy commands: forward to same handlers
bot.onText(/\/new/, (msg) => handleNewProxyRequest(msg.chat.id));
bot.onText(/\/list/, (msg) => handleListRequest(msg.chat.id));
bot.onText(/\/status/, (msg) => handleStatusRequest(msg.chat.id));
bot.onText(/\/delete/, (msg) => handleDeleteMenu(msg.chat.id, 0));

// We do not use plain text states any more, so ignore non-command messages
bot.on("message", (msg) => {
  if (msg.text && msg.text.startsWith("/")) return;
  // no interactive text flows for now
});

// Single callback_query handler
bot.on("callback_query", async (query) => {
  const chatId = query.message.chat.id;
  const data = query.data || "";

  try {
    switch (data) {
      case "menu_list":
        await handleListRequest(chatId, query);
        break;

      case "menu_new":
        await handleNewProxyRequest(chatId, query);
        break;

      case "menu_status":
        await handleStatusRequest(chatId, query);
        break;

      case "menu_delete":
        await handleDeleteMenu(chatId, 0, query);
        break;

      case "back_main":
        await bot.editMessageText("Select an option:", {
          chat_id: chatId,
          message_id: query.message.message_id,
          ...mainMenuKeyboard()
        });
        break;

      default:
        if (data.startsWith("del_page:")) {
          const page = parseInt(data.split(":")[1] || "0", 10) || 0;
          await handleDeleteMenu(chatId, page, query);
        } else if (data.startsWith("del_proxy:")) {
          const id = data.split(":")[1];
          await handleDeleteProxy(chatId, id, query);
        }
        break;
    }
  } catch (e) {
    console.error("callback_query handler error:", e);
    // best-effort user feedback
    bot.answerCallbackQuery(query.id, { text: "Error, please try again." });
  }

  // Answer callback to remove loading animation
  try {
    await bot.answerCallbackQuery(query.id);
  } catch (_) {}
});

// ---- High-level handlers ----

// 1) New proxy: one click = one proxy
async function handleNewProxyRequest(chatId, query) {
  if (query) await bot.answerCallbackQuery(query.id);

  await bot.sendMessage(chatId, "Creating a new proxy, please wait...");

  let out;
  try {
    out = await runScriptAsync("new_proxy.sh", []);
  } catch (err) {
    await bot.sendMessage(
      chatId,
      `Error creating proxy: ${err.message || "script failed"}`
    );
    return;
  }

  const lines = out.split("\n").filter(Boolean);
  if (lines.length === 0) {
    await bot.sendMessage(
      chatId,
      "Proxy script did not return any data. Please check new_proxy.sh."
    );
    return;
  }

  // Expect first line to describe the newly created proxy
  const proxy = parseProxyLine(lines[0], 0);
  const link = buildProxyLink(proxy.secret, proxy.port);

  let text = "New proxy created.\n";
  text += `Name: ${proxy.name}\n`;
  text += `Port: \`${proxy.port || config.defaultPort}\`\n`;
  text += `Secret: \`${proxy.secret}\`\n`;
  text += `Link:\n${link}`;

  const keyboard = {
    reply_markup: {
      inline_keyboard: [
        [{ text: "🔗 Connect proxy", url: link }],
        [{ text: "⬅ Back to main menu", callback_data: "back_main" }]
      ]
    },
    parse_mode: "Markdown"
  };

  await bot.sendMessage(chatId, text, keyboard);
}

// 2) List all proxies (with connect buttons)
async function handleListRequest(chatId, query) {
  if (query) await bot.answerCallbackQuery(query.id);

  let out;
  try {
    out = await runScriptAsync("list_proxies.sh", []);
  } catch (err) {
    await bot.sendMessage(
      chatId,
      "Error: could not list proxies. Please check server scripts."
    );
    return;
  }

  const proxies = parseProxyList(out);
  if (proxies.length === 0) {
    await bot.sendMessage(
      chatId,
      'There are no proxies yet.\nUse "New proxy" to create one.'
    );
    return;
  }

  let text = `Total proxies: ${proxies.length}\n\n`;
  proxies.forEach((p, idx) => {
    const link = buildProxyLink(p.secret, p.port);
    text += `${idx + 1}. ${p.name} (port: ${p.port || "?"})\n${link}\n\n`;
  });

  const kb = buildProxyListKeyboard(proxies);

  await bot.sendMessage(chatId, text, {
    reply_markup: kb
  });
}

// 3) Status: show per-port ONLINE/OFFLINE + raw stats output
async function handleStatusRequest(chatId, query) {
  if (query) await bot.answerCallbackQuery(query.id);

  let listOut = "";
  let statsOut = "";

  try {
    // List proxies to check each port status
    listOut = await runScriptAsync("list_proxies.sh", []);
  } catch (err) {
    listOut = "";
  }

  try {
    // Optional: extra stats script (may fail, it's fine)
    statsOut = await runScriptAsync("stats_proxy.sh", []);
  } catch (err) {
    statsOut = "";
  }

  const proxies = parseProxyList(listOut);
  let text = "Stats:\n";

  if (proxies.length === 0) {
    text += "Stored proxies: 0\n\n";
  } else {
    text += `Stored proxies: ${proxies.length}\n\n`;
    text += "Per-proxy status (by port):\n";

    const statuses = await Promise.all(
      proxies.map((p) => checkPortStatus(p.port))
    );

    proxies.forEach((p, idx) => {
      const st = statuses[idx];
      text += ` • ${p.name} (port ${p.port || "?"}) → ${st}\n`;
    });

    text += "\n";
  }

  if (statsOut) {
    text += "Raw stats from server:\n";
    text += statsOut;
  } else {
    text += "No extra stats available (stats script not reachable).";
  }

  await bot.sendMessage(chatId, text);
}

// 4) Delete menu (paginated)
async function handleDeleteMenu(chatId, page = 0, query) {
  if (query) await bot.answerCallbackQuery(query.id);

  let out;
  try {
    out = await runScriptAsync("list_proxies.sh", []);
  } catch (err) {
    await bot.sendMessage(chatId, "Error: could not list proxies.");
    return;
  }

  const proxies = parseProxyList(out);
  if (proxies.length === 0) {
    await bot.sendMessage(chatId, "There are no proxies to delete.");
    return;
  }

  const kb = buildDeleteKeyboard(proxies, page);
  const text = `Select a proxy to delete:\nTotal proxies: ${proxies.length}`;

  if (query) {
    await bot.editMessageText(text, {
      chat_id: chatId,
      message_id: query.message.message_id,
      reply_markup: kb.inline_keyboard
    });
  } else {
    await bot.sendMessage(chatId, text, { reply_markup: kb.inline_keyboard });
  }
}

// 5) Delete proxy by id
async function handleDeleteProxy(chatId, id, query) {
  try {
    const out = await runScriptAsync("delete_proxy.sh", [id]);
    await bot.answerCallbackQuery(query.id, { text: "Proxy removed." });
    await bot.sendMessage(
      chatId,
      `Proxy removed.\n${out ? String(out) : ""}`
    );
  } catch (err) {
    await bot.answerCallbackQuery(query.id, { text: "Error deleting proxy" });
    await bot.sendMessage(
      chatId,
      `Error deleting proxy: ${err.message || "script failed"}`
    );
  }
}
