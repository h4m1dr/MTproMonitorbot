# comments MUST be English only
import math
import secrets

from telegram import (
    InlineKeyboardMarkup,
    InlineKeyboardButton,
    Update,
)
from telegram.ext import (
    Application,
    CommandHandler,
    CallbackQueryHandler,
    ContextTypes,
)

from .config import Config
from .db import Database
from .mtproxy_manager import MtproxyManager
from .utils import admin_only, is_authorized


PAGE_SIZE = 6  # proxies per page


class MtproxyBotApp:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.db = Database(cfg.db_path)
        self.mt = MtproxyManager(cfg)

    # ---------- keyboards ----------

    def main_menu_keyboard(self) -> InlineKeyboardMarkup:
        keyboard = [
            [
                InlineKeyboardButton("Proxy list", callback_data="menu_proxy_list"),
                InlineKeyboardButton("New proxy", callback_data="menu_new_proxy"),
            ],
            [
                InlineKeyboardButton("Status", callback_data="menu_status"),
                InlineKeyboardButton("Delete proxy", callback_data="menu_delete_proxy"),
            ],
            [
                InlineKeyboardButton("Settings", callback_data="menu_settings"),
            ],
        ]
        return InlineKeyboardMarkup(keyboard)

    def proxy_list_keyboard(self, admin_id: int, page: int) -> InlineKeyboardMarkup:
        total = self.db.total_proxies_for_admin(admin_id)
        pages = max(1, math.ceil(total / PAGE_SIZE))
        page = max(0, min(page, pages - 1))
        offset = page * PAGE_SIZE

        proxies = self.db.list_proxies_for_admin(admin_id, offset=offset, limit=PAGE_SIZE)

        rows = []

        # Up to 6 proxies, 2 rows of 3 buttons (or fewer if not enough)
        # Each button is URL button with proxy link
        for i in range(0, len(proxies), 3):
            sub = proxies[i : i + 3]
            btn_row = []
            for p in sub:
                proxy_id = p["id"]
                label = p["label"]
                # We cannot prebuild URL without secrets; build link from secret
                proxy_link = self.mt.build_proxy_link(p["secret"])
                btn_row.append(
                    InlineKeyboardButton(text=label, url=proxy_link)
                )
            rows.append(btn_row)

        # Navigation row
        nav_row = []
        if pages > 1:
            # previous / next with page encoded
            if page > 0:
                nav_row.append(
                    InlineKeyboardButton(
                        "⬅️ Prev", callback_data=f"proxy_page:{page-1}"
                    )
                )
            if page < pages - 1:
                nav_row.append(
                    InlineKeyboardButton(
                        "Next ➡️", callback_data=f"proxy_page:{page+1}"
                    )
                )

        if nav_row:
            rows.append(nav_row)

        # Back button always at bottom
        rows.append(
            [InlineKeyboardButton("🔙 Back", callback_data="back_to_main")]
        )

        return InlineKeyboardMarkup(rows)

    # ---------- handlers ----------

    @admin_only_cfg := None  # placeholder, will be set after class definition
    async def start(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        assert user is not None

        # Ensure admin row exists
        is_owner = user.id == self.cfg.owner_id
        self.db.ensure_admin(
            telegram_id=user.id,
            display_name=user.full_name,
            is_owner=is_owner,
        )

        await update.message.reply_text(
            "سلام 👋\n"
            "به پنل مدیریت MTProto خوش اومدی.\n\n"
            "از منوی زیر انتخاب کن:",
            reply_markup=self.main_menu_keyboard(),
        )

    @admin_only_cfg
    async def handle_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        query = update.callback_query
        if not query:
            return

        user = query.from_user
        admin_row = self.db.get_admin_by_telegram(user.id)
        if not admin_row:
            await query.answer()
            return

        admin_id = admin_row["id"]
        data = query.data or ""

        if data == "back_to_main":
            await query.answer()
            await query.edit_message_text(
                "منوی اصلی:",
                reply_markup=self.main_menu_keyboard(),
            )
            return

        if data == "menu_proxy_list":
            await query.answer()
            kb = self.proxy_list_keyboard(admin_id=admin_id, page=0)
            total = self.db.total_proxies_for_admin(admin_id)
            text = f"لیست پروکسی‌های شما (تعداد: {total}):"
            await query.edit_message_text(text, reply_markup=kb)
            return

        if data.startswith("proxy_page:"):
            page_str = data.split(":", 1)[1]
            try:
                page = int(page_str)
            except ValueError:
                page = 0
            await query.answer()
            kb = self.proxy_list_keyboard(admin_id=admin_id, page=page)
            total = self.db.total_proxies_for_admin(admin_id)
            text = f"لیست پروکسی‌های شما (تعداد: {total}) - صفحه {page + 1}:"
            await query.edit_message_text(text, reply_markup=kb)
            return

        if data == "menu_new_proxy":
            await query.answer()
            # For simplicity: auto-generate secret and label
            await self.create_new_proxy_for_admin(query, admin_row)
            return

        # TODO: handle status, delete_proxy, settings

    async def create_new_proxy_for_admin(self, query, admin_row):
        admin_id = admin_row["id"]
        tag_prefix = admin_row["tag_prefix"]

        # If admin has no tag yet, ask them to set one
        if not tag_prefix:
            await query.edit_message_text(
                "هنوز برای خودت تگ تنظیم نکردی.\n"
                "یک تگ بنویس (مثلاً hproxy یا zproxy):\n\n"
                "بعد از این هر پروکسی با این تگ + شماره ساخته می‌شود."
            )
            # You should set a flag in user_data to capture next message as tag;
            # omitted here for brevity.
            return

        # Generate secret and register in MTProxy
        secret = self.mt.add_secret()  # generates if None
        # Determine next index for this admin
        count = self.db.count_proxies_for_admin(admin_id)
        index = count + 1
        label = f"{tag_prefix} {index}"

        proxy_id = self.db.create_proxy(admin_id=admin_id, label=label, secret=secret)
        link = self.mt.build_proxy_link(secret)

        kb = InlineKeyboardMarkup(
            [
                [InlineKeyboardButton(label, url=link)],
                [InlineKeyboardButton("🔙 Back", callback_data="back_to_main")],
            ]
        )

        await query.edit_message_text(
            f"پروکسی جدید ساخته شد:\n\n"
            f"نام: {label}\n"
            f"ID: {proxy_id}",
            reply_markup=kb,
        )


# Fix decorator now that Config exists
cfg_for_decorator = Config.from_env()


def admin_only_cfg(func):
    return admin_only(cfg_for_decorator)(func)


def main():
    cfg = Config.from_env()
    if not cfg.bot_token or not cfg.owner_id:
        raise RuntimeError("BOT_TOKEN or OWNER_ID not set in .env")

    app_logic = MtproxyBotApp(cfg)

    application = Application.builder().token(cfg.bot_token).build()

    # Wrap handlers with admin_only via utils
    application.add_handler(CommandHandler("start", admin_only(cfg)(app_logic.start)))
    application.add_handler(
        CallbackQueryHandler(admin_only(cfg)(app_logic.handle_callback))
    )

    application.run_polling()


if __name__ == "__main__":
    main()
