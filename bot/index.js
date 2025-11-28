// bot/index.js
// MTPro Monitor Bot - Telegram interface

const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');
const TelegramBot = require('node-telegram-bot-api');

// This line is replaced by installer script (mtpromonitor.sh)
const TOKEN = "TOKEN_HERE";

if (!TOKEN || TOKEN === "TOKEN_HERE") {
  console.error("ERROR: Bot token is not set. Run the installer script first.");
  process.exit(1);
}

// Paths
const ROOT_DIR = path.join(__dirname, '..');
const DATA_DIR = path.join(ROOT_DIR, 'data');
const SCRIPTS_DIR = path.join(ROOT_DIR, 'scripts');
const CONFIG_PATH = path.join(DATA_DIR, 'config.json');

// Default config values
const DEFAULT_CONFIG = {
  publicHost: "",   // VPS public IP
  dnsName: "",      // Optional domain name
  defaultPort: 443  // Default port for new proxies
};

// Ensure data directory exists
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// Load/save config helpers
function loadConfig() {
  try {
    const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
    const cfg = JSON.parse(raw);
    return { ...DEFAULT_CONFIG, ...cfg };
  } catch (e) {
    return { ...DEFAULT_CONFIG };
  }
}

function saveConfig(cfg) {
  const merged = { ...DEFAULT_CONFIG, ...cfg };
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(merged, null, 2));
  return merged;
}

let config = loadConfig();

// Simple per-chat state (for asking text input)
const state = {}; // { [chatId]: { mode: 'set_ip' | 'set_dns' | 'set_port' | 'new_proxy_port' } }

const bot = new TelegramBot(TOKEN, { polling: true });

// ===== Keyboards =====

function mainMenuKeyboard() {
  return {
    reply_markup: {
      inline_keyboard: [
        [
          { text: 'View all proxies', callback_data: 'menu_list' },
          { text: 'New proxy',        callback_data: 'menu_new' }
        ],
        [
          { text: 'Status',           callback_data: 'menu_status' },
          { text: 'Delete proxy',     callback_data: 'menu_delete' }
        ],
        [
          { text: 'Settings (IP / DNS / Port)', callback_data: 'menu_settings' }
        ]
      ]
    }
  };
}

function settingsKeyboard() {
  const hostInfo = config.publicHost ? config.publicHost : 'not set';
  const dnsInfo  = config.dnsName    ? config.dnsName    : 'not set';
  const portInfo = config.defaultPort;

  return {
    reply_markup: {
      inline_keyboard: [
        [{ text: `Set public IP/host (${hostInfo})`, callback_data: 'set_ip' }],
        [{ text: `Set DNS / domain (${dnsInfo})`,    callback_data: 'set_dns' }],
        [{ text: `Set default port (${portInfo})`,   callback_data: 'set_port' }],
        [{ text: '⬅ Back to main menu',              callback_data: 'back_main' }]
      ]
    }
  };
}

// Build inline keyboard for deleting proxies with pagination
function buildDeleteKeyboard(proxies, page = 0, perPage = 8) {
  const start = page * perPage;
  const slice = proxies.slice(start, start + perPage);

  const rows = [];
  for (let i = 0; i < slice.length; i += 4) {
    const row = slice.slice(i, i + 4).map(p => ({
      text: p.name,
      callback_data: `del_proxy:${p.id}`
    }));
    rows.push(row);
  }

  const totalPages = Math.ceil(proxies.length / perPage);
  const navRow = [];

  if (page > 0) {
    navRow.push({ text: '⬅ Prev', callback_data: `del_page:${page - 1}` });
  }
  if (page < totalPages - 1) {
    navRow.push({ text: 'Next ➡', callback_data: `del_page:${page + 1}` });
  }
  if (navRow.length > 0) rows.push(navRow);

  return { inline_keyboard: rows };
}

// ===== Helpers to call shell scripts =====

function runScript(scriptName, args = [], callback) {
  const scriptPath = path.join(SCRIPTS_DIR, scriptName);
  execFile('bash', [scriptPath, ...args], (err, stdout, stderr) => {
    if (err) {
      console.error(`Script ${scriptName} failed:`, stderr || err.message);
      return callback(err, null);
    }
    callback(null, stdout.trim());
  });
}

// Parse list_proxies.sh output into objects
// Expected example format per line: id secret port name
function parseProxyList(output) {
  if (!output || output === 'NO_PROXIES') return [];
  const lines = output.split('\n').map(l => l.trim()).filter(Boolean);
  return lines.map((line, idx) => {
    const parts = line.split(/\s+/);
    return {
      id: parts[0] || String(idx),   // internal id to delete
      secret: parts[1] || '',
      port: parts[2] || '',
      name: parts[3] || parts[1] || `proxy_${idx + 1}`
    };
  });
}

// Build proxy link using config (DNS or IP)
function buildProxyLink(secret, port) {
  const host = config.dnsName || config.publicHost || 'YOUR_IP_HERE';
  return `tg://proxy?server=${host}&port=${port}&secret=${secret}`;
}

// ===== Commands & Handlers =====

// /start
bot.onText(/\/start/, (msg) => {
  const chatId = msg.chat.id;
  bot.sendMessage(chatId, 'Select an option:', mainMenuKeyboard());
});

// Optional: still support /new, /list, /status, /delete by forwarding to handlers
bot.onText(/\/new/, (msg) => {
  handleNewProxyRequest(msg.chat.id);
});
bot.onText(/\/list/, (msg) => {
  handleListRequest(msg.chat.id);
});
bot.onText(/\/status/, (msg) => {
  handleStatusRequest(msg.chat.id);
});
bot.onText(/\/delete/, (msg) => {
  handleDeleteMenu(msg.chat.id, 0);
});

// Text input handler (for IP/DNS/Port etc.)
bot.on('message', (msg) => {
  const chatId = msg.chat.id;
  const st = state[chatId];

  // Ignore commands (starting with '/')
  if (!st || (msg.text && msg.text.startsWith('/'))) return;
  const text = (msg.text || '').trim();

  if (st.mode === 'set_ip') {
    config.publicHost = text;
    config = saveConfig(config);
    state[chatId] = null;
    bot.sendMessage(chatId, `Public host set to: ${text}`, settingsKeyboard());
    return;
  }

  if (st.mode === 'set_dns') {
    config.dnsName = text;
    config = saveConfig(config);
    state[chatId] = null;
    bot.sendMessage(chatId, `DNS / domain set to: ${text}`, settingsKeyboard());
    return;
  }

  if (st.mode === 'set_port') {
    const port = parseInt(text, 10);
    if (!port || port <= 0 || port > 65535) {
      bot.sendMessage(chatId, 'Invalid port. Please send a number between 1 and 65535.');
      return;
    }
    config.defaultPort = port;
    config = saveConfig(config);
    state[chatId] = null;
    bot.sendMessage(chatId, `Default port set to: ${port}`, settingsKeyboard());
    return;
  }

  if (st.mode === 'new_proxy_port') {
    const port = parseInt(text, 10);
    if (!port || port <= 0 || port > 65535) {
      bot.sendMessage(chatId, 'Invalid port. Please send a number between 1 and 65535.');
      return;
    }
    state[chatId] = null;
    createNewProxy(chatId, port);
    return;
  }
});

// Callback query handler (inline keyboard)
bot.on('callback_query', (query) => {
  const chatId = query.message.chat.id;
  const data = query.data || '';

  // Main menu routes
  if (data === 'menu_list') {
    bot.answerCallbackQuery(query.id);
    handleListRequest(chatId, query);
    return;
  }
  if (data === 'menu_new') {
    bot.answerCallbackQuery(query.id);
    handleNewProxyRequest(chatId, query);
    return;
  }
  if (data === 'menu_status') {
    bot.answerCallbackQuery(query.id);
    handleStatusRequest(chatId, query);
    return;
  }
  if (data === 'menu_delete') {
    bot.answerCallbackQuery(query.id);
    handleDeleteMenu(chatId, 0, query);
    return;
  }
  if (data === 'menu_settings') {
    bot.answerCallbackQuery(query.id);
    bot.editMessageText('Settings (IP / DNS / Port):', {
      chat_id: chatId,
      message_id: query.message.message_id,
      ...settingsKeyboard()
    });
    return;
  }
  if (data === 'back_main') {
    bot.answerCallbackQuery(query.id);
    bot.editMessageText('Select an option:', {
      chat_id: chatId,
      message_id: query.message.message_id,
      ...mainMenuKeyboard()
    });
    return;
  }

  // Settings actions
  if (data === 'set_ip') {
    state[chatId] = { mode: 'set_ip' };
    bot.answerCallbackQuery(query.id);
    bot.sendMessage(chatId, 'Send the public IP / host to use in proxy links (e.g. 109.120.134.99).');
    return;
  }
  if (data === 'set_dns') {
    state[chatId] = { mode: 'set_dns' };
    bot.answerCallbackQuery(query.id);
    bot.sendMessage(chatId, 'Send the DNS / domain name to use in proxy links (e.g. proxy.example.com).');
    return;
  }
  if (data === 'set_port') {
    state[chatId] = { mode: 'set_port' };
    bot.answerCallbackQuery(query.id);
    bot.sendMessage(chatId, 'Send the default port number for new proxies (e.g. 443).');
    return;
  }

  // New proxy port options
  if (data === 'new_use_default') {
    bot.answerCallbackQuery(query.id);
    createNewProxy(chatId, config.defaultPort, 'default');
    return;
  }
  if (data === 'new_custom_port') {
    bot.answerCallbackQuery(query.id);
    state[chatId] = { mode: 'new_proxy_port' };
    bot.sendMessage(chatId, 'Send the port number you want to use:');
    return;
  }
  if (data === 'new_auto_port') {
    bot.answerCallbackQuery(query.id);
    createNewProxy(chatId, null, 'auto');
    return;
  }

  // Delete menu pagination
  if (data.startsWith('del_page:')) {
    const page = parseInt(data.split(':')[1] || '0', 10) || 0;
    bot.answerCallbackQuery(query.id);
    handleDeleteMenu(chatId, page, query);
    return;
  }

  // Delete specific proxy
  if (data.startsWith('del_proxy:')) {
    const id = data.split(':')[1];
    bot.answerCallbackQuery(query.id);
    handleDeleteProxy(chatId, id, query);
    return;
  }

  bot.answerCallbackQuery(query.id);
});

// ===== Handlers =====

function handleNewProxyRequest(chatId, query) {
  const portInfo = config.defaultPort;
  const text =
    `New proxy:\n` +
    `Current default port: ${portInfo}\n\n` +
    `Choose how to set the port:`;
  const kb = {
    reply_markup: {
      inline_keyboard: [
        [{ text: `Use default port (${portInfo})`, callback_data: 'new_use_default' }],
        [{ text: 'Choose custom port',            callback_data: 'new_custom_port' }],
        [{ text: 'Auto-select free port',         callback_data: 'new_auto_port' }]
      ]
    }
  };

  if (query) {
    bot.editMessageText(text, {
      chat_id: chatId,
      message_id: query.message.message_id,
      ...kb
    });
  } else {
    bot.sendMessage(chatId, text, kb);
  }
}

// Create new proxy via script
function createNewProxy(chatId, port, mode = 'default') {
  const args = [];

  if (config.publicHost) {
    args.push('--host', config.publicHost);
  }
  if (config.dnsName) {
    args.push('--dns', config.dnsName);
  }

  if (mode === 'default' && port) {
    args.push('--port', String(port));
  } else if (mode === 'auto') {
    args.push('--port', 'auto');
  } else if (port) {
    args.push('--port', String(port));
  }

  runScript('new_proxy.sh', args, (err, out) => {
    if (err) {
      bot.sendMessage(chatId, `Error creating proxy: ${err.message}`);
      return;
    }

    // Expect script to print something like: "SECRET PORT"
    const lines = out.split('\n').filter(Boolean);
    const first = lines[0] || '';
    const parts = first.split(/\s+/);
    const secret = parts[0] || '';
    const realPort = parts[1] || port || config.defaultPort;
    const link = buildProxyLink(secret, realPort);

    let msg = 'New proxy created.\n';
    msg += `Secret: \`${secret}\`\n`;
    msg += `Port: \`${realPort}\`\n`;
    msg += `Link:\n${link}`;

    bot.sendMessage(chatId, msg, { parse_mode: 'Markdown' });
  });
}

// List proxies
function handleListRequest(chatId, query) {
  runScript('list_proxies.sh', [], (err, out) => {
    if (err) {
      bot.sendMessage(chatId, 'Error: could not list proxies. Please check server scripts.');
      return;
    }
    const proxies = parseProxyList(out);
    if (proxies.length === 0) {
      bot.sendMessage(chatId, 'There are no proxies yet. Use "New proxy" to create one.');
      return;
    }
    let text = `Total proxies: ${proxies.length}\n\n`;
    proxies.forEach((p, idx) => {
      const link = buildProxyLink(p.secret, p.port);
      text += `${idx + 1}. ${p.name} (port: ${p.port})\n${link}\n\n`;
    });
    bot.sendMessage(chatId, text);
  });
}

// Status
function handleStatusRequest(chatId, query) {
  runScript('stats_proxy.sh', [], (err, out) => {
    if (err) {
      bot.sendMessage(chatId, 'Error: could not read proxy stats. Please check stats script.');
      return;
    }
    const text = out || 'No stats available.';
    bot.sendMessage(chatId, `Stats:\n${text}`);
  });
}

// Delete menu (paginated)
function handleDeleteMenu(chatId, page = 0, query) {
  runScript('list_proxies.sh', [], (err, out) => {
    if (err) {
      bot.sendMessage(chatId, 'Error: could not list proxies.');
      return;
    }
    const proxies = parseProxyList(out);
    if (proxies.length === 0) {
      bot.sendMessage(chatId, 'There are no proxies to delete.');
      return;
    }

    const kb = buildDeleteKeyboard(proxies, page);
    const text = `Select a proxy to delete:\nTotal proxies: ${proxies.length}`;
    if (query) {
      bot.editMessageText(text, {
        chat_id: chatId,
        message_id: query.message.message_id,
        reply_markup: kb
      });
    } else {
      bot.sendMessage(chatId, text, { reply_markup: kb });
    }
  });
}

// Delete proxy by id
function handleDeleteProxy(chatId, id, query) {
  runScript('delete_proxy.sh', [id], (err, out) => {
    if (err) {
      bot.sendMessage(chatId, `Error deleting proxy: ${err.message}`);
      return;
    }
    const msg = out || 'Proxy removed.';
    bot.sendMessage(chatId, msg);
  });
}
