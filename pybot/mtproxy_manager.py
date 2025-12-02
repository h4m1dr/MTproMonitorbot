# comments MUST be English only
from __future__ import annotations

import re
import secrets
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

from .config import Config


SERVICE_PATHS = [
    "/etc/systemd/system",
    "/lib/systemd/system",
    "/usr/lib/systemd/system",
]


@dataclass
class MTProxyConfig:
    secrets: List[str]
    port: int
    tls_domain: Optional[str]


class MTProxyManager:
    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg
        self.service_name = cfg.service_name

    # ----- service helpers -----
    def _find_service_file(self) -> Path:
        candidates = [
            f"{self.service_name}.service",
            f"{self.service_name.lower()}.service",
        ]
        for base in SERVICE_PATHS:
            for name in candidates:
                p = Path(base) / name
                if p.exists():
                    return p
        raise FileNotFoundError("MTProxy systemd service file not found")

    def _load_service_text(self) -> str:
        path = self._find_service_file()
        return path.read_text(encoding="utf-8")

    def _save_service_text(self, text: str) -> None:
        path = self._find_service_file()
        path.write_text(text, encoding="utf-8")

    # ----- parse / build config -----
    def parse_config(self) -> MTProxyConfig:
        text = self._load_service_text()
        m = re.search(r"^ExecStart=(.+)$", text, flags=re.MULTILINE)
        if not m:
            raise RuntimeError("ExecStart not found in service file")
        cmd = m.group(1).strip()
        args = shlex.split(cmd)

        secrets_list: List[str] = []
        port: Optional[int] = None

        i = 0
        while i < len(args):
            token = args[i]
            if token in ("-S", "--secret"):
                if i + 1 < len(args):
                    secrets_list.append(args[i + 1])
                    i += 2
                    continue
            if token in ("-p", "--port"):
                if i + 1 < len(args):
                    try:
                        port = int(args[i + 1])
                    except ValueError:
                        pass
                    i += 2
                    continue
            i += 1

        if port is None:
            port = self.cfg.port or 443

        return MTProxyConfig(
            secrets=secrets_list,
            port=port,
            tls_domain=self.cfg.tls_domain,
        )

    def _write_config(self, cfg: MTProxyConfig) -> None:
        text = self._load_service_text()
        m = re.search(r"^ExecStart=(.+)$", text, flags=re.MULTILINE)
        if not m:
            raise RuntimeError("ExecStart not found when writing config")

        cmd = m.group(1).strip()
        args = shlex.split(cmd)

        new_args: List[str] = []
        i = 0
        while i < len(args):
            token = args[i]
            if token in ("-S", "--secret"):
                i += 2
                continue
            new_args.append(token)
            i += 1

        for s in cfg.secrets:
            new_args.extend(["-S", s])

        new_cmd = " ".join(shlex.quote(a) for a in new_args)
        new_exec_line = "ExecStart=" + new_cmd

        new_text = re.sub(
            r"^ExecStart=.+$",
            new_exec_line,
            text,
            flags=re.MULTILINE,
        )
        self._save_service_text(new_text)
        self._reload_and_restart()

    def _reload_and_restart(self) -> None:
        subprocess.run(["systemctl", "daemon-reload"], check=True)
        subprocess.run(["systemctl", "restart", self.service_name], check=True)

    # ----- secrets management -----
    def list_secrets(self) -> List[str]:
        return self.parse_config().secrets

    def create_secret(self) -> str:
        # 16 bytes = 32 hex chars
        return secrets.token_hex(16)

    def add_secret(self, secret: Optional[str] = None) -> str:
        if secret is None:
            secret = self.create_secret()

        cfg = self.parse_config()
        if secret in cfg.secrets:
            return secret

        cfg.secrets.append(secret)
        self._write_config(cfg)
        return secret

    def remove_secret(self, secret: str) -> bool:
        cfg = self.parse_config()
        if secret not in cfg.secrets:
            return False
        cfg.secrets = [s for s in cfg.secrets if s != secret]
        self._write_config(cfg)
        return True

    # ----- link helpers -----
    def get_public_ip(self) -> str:
        try:
            out = subprocess.check_output(
                ["curl", "-4", "-s", "https://api.ipify.org"],
                text=True,
                timeout=10,
            )
            ip = out.strip()
            if ip:
                return ip
        except Exception:
            pass
        return "127.0.0.1"

    def build_proxy_link(self, secret: str) -> str:
        cfg = self.parse_config()
        server_ip = self.get_public_ip()
        port = cfg.port

        if cfg.tls_domain:
            hex_domain = cfg.tls_domain.encode("utf-8").hex().lower()
            full_secret = "ee" + secret + hex_domain
        else:
            full_secret = "dd" + secret

        return f"tg://proxy?server={server_ip}&port={port}&secret={full_secret}"
