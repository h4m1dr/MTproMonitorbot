from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional


@dataclass
class Config:
    bot_token: str
    owner_ids: List[int] = field(default_factory=list)
    service_name: str = "MTProxy"
    db_path: str = "data/proxies.sqlite3"
    tls_domain: Optional[str] = None
    port: Optional[int] = None

    @classmethod
    def from_file(cls, path: str | Path = "config.json") -> "Config":
        p = Path(path)
        data = json.loads(p.read_text(encoding="utf-8"))
        return cls(
            bot_token=data["bot_token"],
            owner_ids=[int(x) for x in data.get("owner_ids", [])],
            service_name=data.get("service_name", "MTProxy"),
            db_path=data.get("db_path", "data/proxies.sqlite3"),
            tls_domain=data.get("tls_domain"),
            port=data.get("port"),
        )
