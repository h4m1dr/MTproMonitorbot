// bot/index.js
// MTPro Monitor Bot - Telegram interface

const fs = require("fs");
const path = require("path");
const { execFile } = require("child_process");
const TelegramBot = require("node-telegram-bot-api");

// This line is replaced by installer script (mtpromonitor.sh)
const TOKEN = "TOKEN_HERE";

if (!TOKEN || TOKEN === "TOKEN_HERE") {
  console.error("ERROR: Bot token is not set. Run mtpromonitor.sh and set the token first.");
  process.exit(1);
}

const ROOT_DIR = path.join(__dirname, "..");
const SCRIPTS_DIR = path.join(ROOT_DIR, "scripts");
const DATA_DIR = path.join(ROOT_DIR, "data");

if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// ---- Helpers to run shell scripts ----

function runScript(scriptName, args = []) {
  return new Promise((resolve, reject) => {
    const scriptPath = path.join(SCRIPTS_DIR, scriptName);

    execFile(scriptPath, args, { cwd: ROOT_DIR }, (error, stdout, stderr) => {
      if (error) {
        const err = new Error(
          `Script ${scriptName} failed: ${error.message}\nSTDERR: ${stderr || "N/A"}`
        );
        reject(err);
        return;
      }
      resolve(stdout.trim());
    });
  });
}

function getDefaultPort() {
  const file = path.join(DATA_DIR, "default_port");
  try {
    const s = fs.readFileSync(file, "utf8").trim();
    const n = parseInt(s, 10);
    if (!Number.isNaN(n) && n > 0 && n < 65536) return n;
  } catch {
    // ignore
  }
  return 443;
}

// Parse one proxy line: ID SECRET PORT NAME [TG_LINK]
function parseProxyLine(line) {
  const parts = line.trim().split(/\s+/);
  if (parts.length < 4) return null;

  const [id, secret, portStr, ...rest] = parts;
  const port = parseInt(portStr, 10);

  let name = "";
  let tgLink = "";

  if (rest.length === 1) {
    name = rest[0];
  } else if (rest.length >= 2) {
    name = rest.slice(0, rest.length - 1).join(" ");
    tgLink = rest[rest.length - 1];
  }

  return {
    id,
    secret,
    port: Number.isNaN(port) ? null : port,
    name,
    tgLink,
  };
}

function parseProxyList(output) {
  if (!output) return [];
  const lines = output
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !/^NO_PROXIES/i.test(l));

  const proxies = [];
  for (const line of lines) {
    const p = parseProxyLine(line);
    if (p) proxies.push(p);
  }
  return proxies;
}

function proxyToText(p) {
  const lines = [];
  lines.push(`🆔 شناسه: <code>${p.id}</code>`);
  if (p.name) {
    lines.push(`📛 نام: <b>${p.name}</b>`);
  }
  if (p.port) {
    lines.push(`🔌 پورت: <code>${p.port}</code>`);
  }
  lines.push(`🔑 سکرت:\n<code>${p.secret}</code>`);
  if (p.tgLink) {
    lines.push("");
    lines.push(`🔗 لینک آماده:\n<code>${p.tgLink}</code>`);
  }
  return lines.join("\n");
}

// ---- Telegram bot setup ----

const bot = new TelegramBot(TOKEN, { polling: true });

// Simple per-chat state (e.g. waiting for delete ID)
const chatState = new Map();

function mainMenuKeyboard() {
  return {
    reply_markup: {
      keyboard: [
        [{ text: "➕ پروکسی جدید" }],
        [{ text: "📋 لیست پروکسی‌ها" }],
        [{ text: "ℹ️ وضعیت و پورت پیش‌فرض" }],
        [{ text: "🗑 حذف پروکسی" }],
      ],
      resize_keyboard: true,
      one_time_keyboard: false,
    },
  };
}

// ---- Command handlers ----

bot.onText(/^\/start$/, (msg) => {
  const chatId = msg.chat.id;
  const defaultPort = getDefaultPort();
  bot.sendMessage(
    chatId,
    `سلام 👋\n\nاین ربات برای مدیریت MTProto Proxy روی سرور شماست.\n\nپورت پیش‌فرض فعلی: <code>${defaultPort}</code>\n\nاز دکمه‌های زیر استفاده کن.`,
    {
      parse_mode: "HTML",
      ...mainMenuKeyboard(),
    }
  );
});

bot.onText(/^\/help$/, (msg) => {
  const chatId = msg.chat.id;
  bot.sendMessage(
    chatId,
    `راهنما:\n\n` +
      `• از دکمه «➕ پروکسی جدید» برای ساخت سکرت جدید روی پورت پیش‌فرض استفاده کن.\n` +
      `• «📋 لیست پروکسی‌ها» همهٔ پروکسی‌های ثبت‌شده را نشان می‌دهد.\n` +
      `• «ℹ️ وضعیت و پورت پیش‌فرض» وضعیت mtproxy و پورت‌ها را نشان می‌دهد.\n` +
      `• «🗑 حذف پروکسی» اجازه می‌دهد یک پروکسی را با شناسه‌اش حذف کنی.\n\n` +
      `/start برای نمایش منوی اصلی.`,
    {
      parse_mode: "HTML",
      ...mainMenuKeyboard(),
    }
  );
});

bot.onText(/^\/delete\s+(\S+)/, async (msg, match) => {
  const chatId = msg.chat.id;
  const id = (match[1] || "").trim();
  if (!id) {
    bot.sendMessage(chatId, "شناسه پروکسی نامعتبر است.", {
      parse_mode: "HTML",
      ...mainMenuKeyboard(),
    });
    return;
  }
  await doDeleteProxy(chatId, id);
});

// ---- Generic message handler (buttons + simple states) ----

bot.on("message", async (msg) => {
  const chatId = msg.chat.id;
  const text = (msg.text || "").trim();

  if (text.startsWith("/start") || text.startsWith("/help") || text.startsWith("/delete")) {
    return; // already handled
  }

  const state = chatState.get(chatId);

  if (state && state.mode === "await_delete_id") {
    const id = text;
    chatState.delete(chatId);
    await doDeleteProxy(chatId, id);
    return;
  }

  if (text === "➕ پروکسی جدید") {
    await handleCreateProxy(chatId);
    return;
  }

  if (text === "📋 لیست پروکسی‌ها") {
    await handleListProxies(chatId);
    return;
  }

  if (text === "ℹ️ وضعیت و پورت پیش‌فرض") {
    await handleStatus(chatId);
    return;
  }

  if (text === "🗑 حذف پروکسی") {
    chatState.set(chatId, { mode: "await_delete_id" });
    bot.sendMessage(
      chatId,
      "لطفاً شناسه پروکسی‌ای که می‌خواهی حذف شود را ارسال کن (🆔 در لیست پروکسی‌ها).",
      {
        parse_mode: "HTML",
        ...mainMenuKeyboard(),
      }
    );
    return;
  }

  // Fallback
  bot.sendMessage(
    chatId,
    "لطفاً یکی از گزینه‌های منو را انتخاب کن یا از /help استفاده کن.",
    {
      parse_mode: "HTML",
      ...mainMenuKeyboard(),
    }
  );
});

// ---- Feature: Create proxy ----

async function handleCreateProxy(chatId) {
  try {
    const defaultPort = getDefaultPort();
    await bot.sendMessage(
      chatId,
      `⏳ در حال ساخت پروکسی جدید روی پورت پیش‌فرض <code>${defaultPort}</code>...`,
      { parse_mode: "HTML" }
    );

    const out = await runScript("new_proxy.sh");
    const p = parseProxyLine(out);

    if (!p) {
      await bot.sendMessage(
        chatId,
        "❌ ساخت پروکسی با خطا مواجه شد (خروجی اسکریپت قابل‌خواندن نبود).",
        { parse_mode: "HTML" }
      );
      return;
    }

    // Try to detect TG_LINK from the raw output if not parsed
    const tokens = out.trim().split(/\s+/);
    if (!p.tgLink && tokens.length >= 5) {
      p.tgLink = tokens[tokens.length - 1];
    }

    const msgText =
      "✅ پروکسی جدید ساخته شد.\n\n" +
      proxyToText(p) +
      "\n\n⚠️ توجه: این پروکسی روی همان پورتی است که در mtproxy تنظیم کرده‌ای.";

    await bot.sendMessage(chatId, msgText, { parse_mode: "HTML", ...mainMenuKeyboard() });
  } catch (err) {
    console.error(err);
    await bot.sendMessage(
      chatId,
      "❌ هنگام اجرای اسکریپت ساخت پروکسی خطایی رخ داد.\n" +
        "لطفاً روی سرور این دستور را چک کن:\n" +
        "<code>cd /opt/MTproMonitorbot && ./scripts/new_proxy.sh</code>",
      { parse_mode: "HTML", ...mainMenuKeyboard() }
    );
  }
}

// ---- Feature: List proxies ----

async function handleListProxies(chatId) {
  try {
    const out = await runScript("list_proxies.sh");
    if (!out || /^NO_PROXIES/i.test(out.trim())) {
      await bot.sendMessage(
        chatId,
        "هنوز هیچ پروکسی ثبت نشده است. از «➕ پروکسی جدید» استفاده کن.",
        { parse_mode: "HTML", ...mainMenuKeyboard() }
      );
      return;
    }

    const proxies = parseProxyList(out);
    if (!proxies.length) {
      await bot.sendMessage(
        chatId,
        "فایلی از پروکسی‌ها پیدا شد، اما نتوانستم آن را بخوانم.",
        { parse_mode: "HTML", ...mainMenuKeyboard() }
      );
      return;
    }

    const chunks = [];
    let current = [];

    for (const p of proxies) {
      const block = proxyToText(p);
      const joined = current.join("\n\n");
      if ((joined.length + block.length) > 3500 && current.length) {
        chunks.push(joined);
        current = [];
      }
      current.push(block);
    }
    if (current.length) {
      chunks.push(current.join("\n\n"));
    }

    for (let i = 0; i < chunks.length; i++) {
      const header = i === 0 ? "📋 لیست پروکسی‌های ثبت‌شده:\n\n" : "";
      await bot.sendMessage(chatId, header + chunks[i], {
        parse_mode: "HTML",
        ...mainMenuKeyboard(),
      });
    }
  } catch (err) {
    console.error(err);
    await bot.sendMessage(
      chatId,
      "❌ هنگام دریافت لیست پروکسی‌ها خطایی رخ داد.\n" +
        "لطفاً روی سرور این دستور را چک کن:\n" +
        "<code>cd /opt/MTproMonitorbot && ./scripts/list_proxies.sh</code>",
      { parse_mode: "HTML", ...mainMenuKeyboard() }
    );
  }
}

// ---- Feature: Status ----

async function handleStatus(chatId) {
  const defaultPort = getDefaultPort();

  try {
    const out = await runScript("stats_proxy.sh");
    const lines = out.split("\n").map((l) => l.trim());

    let proxyCount = null;
    let byPort = null;
    let mtStatus = null;
    let listening = null;

    for (const line of lines) {
      if (line.startsWith("PROXY_COUNT=")) {
        proxyCount = line.substring("PROXY_COUNT=".length);
      } else if (line.startsWith("BY_PORT=")) {
        byPort = line.substring("BY_PORT=".length);
      } else if (line.startsWith("MTPROXY_SERVICE=")) {
        mtStatus = line.substring("MTPROXY_SERVICE=".length);
      } else if (line.startsWith("LISTENING_PORTS=")) {
        listening = line.substring("LISTENING_PORTS=".length);
      }
    }

    let text = `ℹ️ وضعیت فعلی:\n\nپورت پیش‌فرض: <code>${defaultPort}</code>\n`;

    if (proxyCount !== null) {
      text += `تعداد پروکسی‌های ثبت‌شده در فایل: <b>${proxyCount}</b>\n`;
    }

    if (byPort) {
      text += `پراکسی‌ها بر اساس پورت: <code>${byPort}</code>\n`;
    }

    if (mtStatus) {
      const human =
        mtStatus === "active"
          ? "فعال ✅"
          : mtStatus === "inactive"
          ? "غیرفعال ⛔️"
          : "نامشخص ⚠️";
      text += `وضعیت سرویس mtproxy: <b>${human}</b>\n`;
    }

    if (listening && listening.length > 0) {
      text += `پورت‌های در حال LISTEN:\n<code>${listening}</code>\n`;
    }

    await bot.sendMessage(chatId, text, {
      parse_mode: "HTML",
      ...mainMenuKeyboard(),
    });
  } catch (err) {
    console.error(err);
    await bot.sendMessage(
      chatId,
      `پورت پیش‌فرض فعلی: <code>${defaultPort}</code>\n` +
        "اما خواندن وضعیت سرویس mtproxy با خطا مواجه شد.",
      { parse_mode: "HTML", ...mainMenuKeyboard() }
    );
  }
}

// ---- Feature: Delete proxy ----

async function doDeleteProxy(chatId, id) {
  try {
    const out = await runScript("delete_proxy.sh", [id]);
    const trimmed = (out || "").trim();

    if (trimmed.startsWith("DELETED")) {
      await bot.sendMessage(
        chatId,
        `✅ پروکسی با شناسه <code>${id}</code> حذف شد.`,
        { parse_mode: "HTML", ...mainMenuKeyboard() }
      );
    } else if (trimmed.startsWith("NOT_FOUND")) {
      await bot.sendMessage(
        chatId,
        `⚠️ پروکسی با شناسه <code>${id}</code> پیدا نشد.`,
        { parse_mode: "HTML", ...mainMenuKeyboard() }
      );
    } else {
      await bot.sendMessage(
        chatId,
        "❌ حذف پروکسی با خطا مواجه شد. خروجی اسکریپت:\n<code>" +
          (trimmed || "EMPTY") +
          "</code>",
        { parse_mode: "HTML", ...mainMenuKeyboard() }
      );
    }
  } catch (err) {
    console.error(err);
    await bot.sendMessage(
      chatId,
      "❌ خطا هنگام اجرای delete_proxy.sh.\n" +
        "لطفاً روی سرور این دستور را چک کن:\n" +
        "<code>cd /opt/MTproMonitorbot && ./scripts/delete_proxy.sh " +
        id +
        "</code>",
      { parse_mode: "HTML", ...mainMenuKeyboard() }
    );
  }
}

console.log("MTPro Monitor Bot is running...");
