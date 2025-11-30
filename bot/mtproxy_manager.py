# comments MUST be English only
import os
import re
import secrets
import subprocess
from dataclasses import dataclass
from typing import List, Optional

from .config import Config


SERVICE_PATHS = [
    "/etc/systemd/system",
    "/lib/systemd/system",
    "/usr/lib/systemd/system",
]


@dataclass
class MtproxyConfig:
    exec_start: str
    secrets: List[str]
    port: int
    tls_domain: Optional[str]


class MtproxyManager:
    def __init__(self, cfg: Config):
        self.cfg = cfg

    def _find_service_file(self) -> str:
        for base in SERVICE_PATHS:
            path = os.path.join(base, f"{self.cfg.mtproxy_service}.service")
            if os.path.isfile(path):
                return path
        raise FileNotFoundError(f"Service file for {self.cfg.mtproxy_service} not found")

    def _read_service_file(self) -> str:
        path = self._find_service_file()
        with open(path, "r", encoding="utf-8") as f:
            return f.read()

    def _write_service_file(self, content: str) -> None:
        path = self._find_service_file()
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)

    def parse_config(self) -> MtproxyConfig:
        content = self._read_service_file()
        match = re.search(r"^ExecStart=(.+)$", content, re.MULTILINE)
        if not match:
            raise RuntimeError("ExecStart not found in service file")

        exec_start = match.group(1)
        secrets = re.findall(r"-S\s+([0-9a-fA-F]+)", exec_start)

        port = self.cfg.mtproxy_default_port
        m_port = re.search(r"-H\s+(\d+)", exec_start)
        if m_port:
            port = int(m_port.group(1))

        tls_domain = None
        m_tls = re.search(r"-D\s+(\S+)", exec_start)
        if m_tls:
            tls_domain = m_tls.group(1)

        return MtproxyConfig(
            exec_start=exec_start,
            secrets=secrets,
            port=port,
            tls_domain=tls_domain,
        )

    def _build_exec_start(self, cfg: MtproxyConfig) -> str:
        # Remove existing -S flags
        exec_cmd = re.sub(r"-S\s+[0-9a-fA-F]+\s*", "", cfg.exec_start)
        # Ensure single spaces
        exec_cmd = re.sub(r"\s+", " ", exec_cmd).strip()
        # Append all secrets
        for s in cfg.secrets:
            exec_cmd += f" -S {s}"
        return exec_cmd

    def _replace_exec_start(self, new_exec: str) -> None:
        content = self._read_service_file()
        content = re.sub(
            r"^ExecStart=.*$",
            f"ExecStart={new_exec}",
            content,
            flags=re.MULTILINE,
        )
        self._write_service_file(content)

    def restart_service(self) -> None:
        subprocess.run(["systemctl", "daemon-reload"], check=True)
        subprocess.run(["systemctl", "restart", self.cfg.mtproxy_service], check=True)

    def generate_secret(self) -> str:
        return secrets.token_hex(16)

    def add_secret(self, secret: Optional[str] = None) -> str:
        cfg = self.parse_config()
        if not secret:
            secret = self.generate_secret()
        if secret not in cfg.secrets:
            cfg.secrets.append(secret)
            new_exec = self._build_exec_start(cfg)
            self._replace_exec_start(new_exec)
            self.restart_service()
        return secret

    def remove_secret(self, secret: str) -> None:
        cfg = self.parse_config()
        if secret in cfg.secrets:
            cfg.secrets = [s for s in cfg.secrets if s != secret]
            new_exec = self._build_exec_start(cfg)
            self._replace_exec_start(new_exec)
            self.restart_service()

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

        return f"https://t.me/proxy?server={server_ip}&port={port}&secret={full_secret}"
