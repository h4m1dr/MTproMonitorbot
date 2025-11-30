# comments MUST be English only
import sqlite3
from contextlib import contextmanager
from typing import Optional, List, Dict


class Database:
    def __init__(self, path: str):
        self.path = path
        self._init_db()

    @contextmanager
    def _conn(self):
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()

    def _init_db(self) -> None:
        with self._conn() as conn:
            cur = conn.cursor()
            # Admins table
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS admins (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    telegram_id INTEGER UNIQUE NOT NULL,
                    tag_prefix TEXT,
                    display_name TEXT,
                    is_owner INTEGER DEFAULT 0,
                    is_active INTEGER DEFAULT 1,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
                """
            )
            # Proxies table
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS proxies (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    admin_id INTEGER NOT NULL,
                    label TEXT NOT NULL,
                    secret TEXT NOT NULL,
                    is_active INTEGER DEFAULT 1,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY(admin_id) REFERENCES admins(id)
                )
                """
            )
            conn.commit()

    # ---------- Admin helpers ----------

    def ensure_admin(self, telegram_id: int, display_name: str, is_owner: bool = False) -> int:
        with self._conn() as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT id FROM admins WHERE telegram_id = ?",
                (telegram_id,),
            )
            row = cur.fetchone()
            if row:
                return row["id"]

            cur.execute(
                """
                INSERT INTO admins (telegram_id, display_name, is_owner)
                VALUES (?, ?, ?)
                """,
                (telegram_id, display_name, 1 if is_owner else 0),
            )
            conn.commit()
            return cur.lastrowid

    def get_admin_by_telegram(self, telegram_id: int) -> Optional[sqlite3.Row]:
        with self._conn() as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT * FROM admins WHERE telegram_id = ? AND is_active = 1",
                (telegram_id,),
            )
            return cur.fetchone()

    def set_admin_tag(self, admin_id: int, tag_prefix: str) -> None:
        with self._conn() as conn:
            cur = conn.cursor()
            cur.execute(
                "UPDATE admins SET tag_prefix = ? WHERE id = ?",
                (tag_prefix, admin_id),
            )
            conn.commit()

    # ---------- Proxy helpers ----------

    def count_proxies_for_admin(self, admin_id: int) -> int:
        with self._conn() as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT COUNT(*) AS c FROM proxies WHERE admin_id = ? AND is_active = 1",
                (admin_id,),
            )
            row = cur.fetchone()
            return int(row["c"]) if row else 0

    def create_proxy(
        self,
        admin_id: int,
        label: str,
        secret: str,
    ) -> int:
        with self._conn() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                INSERT INTO proxies (admin_id, label, secret)
                VALUES (?, ?, ?)
                """,
                (admin_id, label, secret),
            )
            conn.commit()
            return cur.lastrowid

    def list_proxies_for_admin(
        self,
        admin_id: int,
        offset: int = 0,
        limit: int = 6,
    ) -> List[sqlite3.Row]:
        with self._conn() as conn:
            cur = conn.cursor()
            cur.execute(
                """
                SELECT * FROM proxies
                WHERE admin_id = ? AND is_active = 1
                ORDER BY id ASC
                LIMIT ? OFFSET ?
                """,
                (admin_id, limit, offset),
            )
            return cur.fetchall()

    def total_proxies_for_admin(self, admin_id: int) -> int:
        return self.count_proxies_for_admin(admin_id)

    def get_proxy_by_id(self, proxy_id: int) -> Optional[sqlite3.Row]:
        with self._conn() as conn:
            cur = conn.cursor()
            cur.execute(
                "SELECT * FROM proxies WHERE id = ?",
                (proxy_id,),
            )
            return cur.fetchone()

    def deactivate_proxy(self, proxy_id: int) -> None:
        with self._conn() as conn:
            cur = conn.cursor()
            cur.execute(
                "UPDATE proxies SET is_active = 0 WHERE id = ?",
                (proxy_id,),
            )
            conn.commit()
