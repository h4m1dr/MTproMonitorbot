# comments MUST be English only
from functools import wraps
from typing import Callable, Awaitable, Any

from telegram import Update
from telegram.ext import ContextTypes

from .config import Config
from .db import Database


def is_authorized(cfg: Config, update: Update) -> bool:
    user = update.effective_user
    if not user:
        return False
    return user.id in cfg.admin_ids


def admin_only(cfg: Config) -> Callable:
    def decorator(func: Callable[[Update, ContextTypes.DEFAULT_TYPE], Awaitable[Any]]):
        @wraps(func)
        async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
            if not is_authorized(cfg, update):
                # Do not respond at all for unauthorized users
                return
            return await func(update, context)

        return wrapper

    return decorator
