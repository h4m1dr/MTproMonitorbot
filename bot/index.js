// MTProxy Manager Bot

const TelegramBot = require("node-telegram-bot-api");
const { exec } = require("child_process");

const TOKEN = "TOKEN_HERE"; // Insert your bot token

const bot = new TelegramBot(TOKEN, { polling: true });

// utility to run scripts
function run(cmd, callback) {
  exec(cmd, (err, stdout, stderr) => {
    if (err) callback("Error: " + err);
    else callback(stdout);
  });
}

bot.onText(/\/start/, msg => {
  bot.sendMessage(msg.chat.id,
    "Welcome to MTProxy Manager Bot\n\n" +
    "/new - create new proxy\n" +
    "/list - list all proxies\n" +
    "/status - show stats\n" +
    "/delete <secret> - remove proxy"
  );
});

bot.onText(/\/new/, msg => {
  run("bash scripts/create_proxy.sh", out =>
    bot.sendMessage(msg.chat.id, "New Proxy Created:\n\n" + out)
  );
});

bot.onText(/\/list/, msg => {
  run("bash scripts/list_proxies.sh", out =>
    bot.sendMessage(msg.chat.id, "Proxy List:\n" + out)
  );
});

bot.onText(/\/delete (.+)/, (msg, match) => {
  run("bash scripts/delete_proxy.sh " + match[1], out =>
    bot.sendMessage(msg.chat.id, out)
  );
});

bot.onText(/\/status/, msg => {
  run("bash scripts/stats_proxy.sh", out =>
    bot.sendMessage(msg.chat.id, "Stats:\n" + out)
  );
});

console.log("Bot is running...");
