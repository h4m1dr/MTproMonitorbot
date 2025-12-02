# comments MUST be English only
from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional


@dataclass
class Proxy:
    id: int
    user_id: int
    secret: str
    link: str
    is_active: bool


class ProxyStore:
    def __init__(self, path: str) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    def _get_conn(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_schema(self) -> None:
        with self._get_conn() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS proxies (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER NOT NULL,
                    secret TEXT NOT NULL,
                    link TEXT NOT NULL,
                    is_active INTEGER NOT NULL DEFAULT 1,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                );
                """
            )

    def add_proxy(self, user_id: int, secret: str, link: str) -> int:
        with self._get_conn() as conn:
            cur = conn.execute(
                "INSERT INTO proxies (user_id, secret, link, is_active) VALUES (?, ?, ?, 1)",
                (user_id, secret, link),
            )
            return int(cur.lastrowid)

    def list_active(self) -> List[Proxy]:
        with self._get_conn() as conn:
            rows = conn.execute(
                "SELECT id, user_id, secret, link, is_active "
                "FROM proxies WHERE is_active = 1 ORDER BY id"
            ).fetchall()
        return [
            Proxy(
                id=row["id"],
                user_id=row["user_id"],
                secret=row["secret"],
                link=row["link"],
                is_active=bool(row["is_active"]),
            )
            for row in rows
        ]

    def get(self, proxy_id: int) -> Optional[Proxy]:
        with self._get_conn() as conn:
            row = conn.execute(
                "SELECT id, user_id, secret, link, is_active "
                "FROM proxies WHERE id = ?",
                (proxy_id,),
            ).fetchone()
        if not row:
            return None
        return Proxy(
            id=row["id"],
            user_id=row["user_id"],
            secret=row["secret"],
            link=row["link"],
            is_active=bool(row["is_active"]),
        )

    def deactivate(self, proxy_id: int) -> None:
        with self._get_conn() as conn:
            conn.execute(
                "UPDATE proxies SET is_active = 0 WHERE id = ?",
                (proxy_id,),
            )
