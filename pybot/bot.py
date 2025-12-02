# comments MUST be English only
from __future__ import annotations

from telegram import (
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    Update,
)
from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
)

from .config import Config
from .db import ProxyStore
from .mtproxy_manager import MTProxyManager


cfg = Config.from_file("config.json")
store = ProxyStore(cfg.db_path)
manager = MTProxyManager(cfg)


def is_admin(user_id: int) -> bool:
    return user_id in cfg.owner_ids


async def ensure_admin(update: Update) -> bool:
    user = update.effective_user
    if not user or not is_admin(user.id):
        if update.message:
            await update.message.reply_text("⛔️ شما دسترسی مدیریت این ربات را ندارید.")
        elif update.callback_query:
            await update.callback_query.answer(
                "⛔️ شما دسترسی مدیریت این ربات را ندارید.", show_alert=True
            )
        return False
    return True


def main_menu_keyboard() -> InlineKeyboardMarkup:
    buttons = [
        [
            InlineKeyboardButton("➕ ساخت پروکسی", callback_data="create_proxy"),
            InlineKeyboardButton("📋 لیست پروکسی‌ها", callback_data="list_proxies"),
        ]
    ]
    return InlineKeyboardMarkup(buttons)


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not await ensure_admin(update):
        return
    text = "سلام 👋\nیکی از گزینه‌های زیر را انتخاب کن:"
    await update.message.reply_text(text, reply_markup=main_menu_keyboard())


async def handle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if not query:
        return
    if not await ensure_admin(update):
        return

    data = query.data or ""
    await query.answer()

    if data == "create_proxy":
        await handle_create_proxy(query)
    elif data == "list_proxies":
        await handle_list_proxies(query)
    elif data.startswith("delete_proxy:"):
        parts = data.split(":", 1)
        if len(parts) == 2 and parts[1].isdigit():
            proxy_id = int(parts[1])
            await handle_delete_proxy(query, proxy_id)
    elif data == "back_to_menu":
        await query.edit_message_text(
            "یکی از گزینه‌های زیر را انتخاب کن:", reply_markup=main_menu_keyboard()
        )


async def handle_create_proxy(query) -> None:
    user = query.from_user
    secret = manager.add_secret()
    link = manager.build_proxy_link(secret)
    proxy_id = store.add_proxy(user_id=user.id, secret=secret, link=link)

    text = (
        "✅ پروکسی جدید ساخته شد.\n\n"
        f"🆔 شناسه: {proxy_id}\n"
        f"👤 مالک: {user.id}\n\n"
        f"🔗 لینک:\n{link}"
    )
    buttons = [
        [InlineKeyboardButton("⬅️ بازگشت به منو", callback_data="back_to_menu")],
    ]
    await query.edit_message_text(text=text, reply_markup=InlineKeyboardMarkup(buttons))


async def handle_list_proxies(query) -> None:
    proxies = store.list_active()
    if not proxies:
        text = "هیچ پروکسی فعالی ثبت نشده است."
        buttons = [
            [InlineKeyboardButton("➕ ساخت پروکسی", callback_data="create_proxy")],
            [InlineKeyboardButton("⬅️ بازگشت به منو", callback_data="back_to_menu")],
        ]
        await query.edit_message_text(
            text=text, reply_markup=InlineKeyboardMarkup(buttons)
        )
        return

    lines = ["📋 لیست پروکسی‌های فعال:\n"]
    buttons = []
    for p in proxies:
        lines.append(f"#{p.id} | 👤 {p.user_id}\n{p.link}\n")
        buttons.append(
            [
                InlineKeyboardButton(
                    f"❌ حذف #{p.id}", callback_data=f"delete_proxy:{p.id}"
                )
            ]
        )
    buttons.append(
        [InlineKeyboardButton("⬅️ بازگشت به منو", callback_data="back_to_menu")]
    )

    text = "\n".join(lines)
    await query.edit_message_text(text=text, reply_markup=InlineKeyboardMarkup(buttons))


async def handle_delete_proxy(query, proxy_id: int) -> None:
    proxy = store.get(proxy_id)
    if not proxy or not proxy.is_active:
        await query.answer("این پروکسی پیدا نشد یا قبلاً حذف شده است.", show_alert=True)
        return

    ok = manager.remove_secret(proxy.secret)
    store.deactivate(proxy_id)

    if ok:
        msg = "✅ پروکسی از MTProxy حذف شد و در دیتابیس غیرفعال شد."
    else:
        msg = "⚠️ در سرویس MTProxy این سکرت پیدا نشد، فقط در دیتابیس غیرفعال شد."

    await query.answer(msg, show_alert=True)
    await handle_list_proxies(query)


def main() -> None:
    application = Application.builder().token(cfg.bot_token).build()
    application.add_handler(CommandHandler("start", cmd_start))
    application.add_handler(CallbackQueryHandler(handle_callback))
    application.run_polling()


if __name__ == "__main__":
    main()
