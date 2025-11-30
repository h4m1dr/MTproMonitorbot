# comments MUST be English only
import os
from dataclasses import dataclass
from dotenv import load_dotenv

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_PATH = os.path.join(BASE_DIR, ".env")

load_dotenv(ENV_PATH)


@dataclass
class Config:
    bot_token: str
    owner_id: int
    admin_ids: list[int]
    mtproxy_service: str
    mtproxy_default_port: int
    mtproxy_tls_domain: str | None
    db_path: str

    @classmethod
    def from_env(cls) -> "Config":
        token = os.getenv("BOT_TOKEN", "").strip()
        owner = int(os.getenv("OWNER_ID", "0") or "0")

        raw_admins = os.getenv("ADMIN_IDS", "").strip()
        admin_ids: list[int] = []
        if raw_admins:
            admin_ids = [int(x) for x in raw_admins.split(",") if x.strip().isdigit()]

        # Always include owner in admin list
        if owner and owner not in admin_ids:
            admin_ids.append(owner)

        service = os.getenv("MTPROXY_SERVICE_NAME", "MTProxy").strip() or "MTProxy"
        port = int(os.getenv("MTPROXY_PORT", "443") or "443")
        tls_domain = os.getenv("MTPROXY_TLS_DOMAIN", "").strip() or None

        db_path = os.getenv("DB_PATH") or os.path.join(BASE_DIR, "data", "mtproxy-bot.db")

        return cls(
            bot_token=token,
            owner_id=owner,
            admin_ids=admin_ids,
            mtproxy_service=service,
            mtproxy_default_port=port,
            mtproxy_tls_domain=tls_domain,
            db_path=db_path,
        )
