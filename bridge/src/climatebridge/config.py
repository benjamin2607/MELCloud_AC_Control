"""Configuration from environment / .env file and the macOS Keychain."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

import keyring

KEYRING_SERVICE = "climatecontrol-melcloud"
TOKEN_PATH = Path.home() / "Library" / "Application Support" / "ClimateControl" / "melcloud.token"


def _load_dotenv(path: Path) -> None:
    """Minimal .env loader (no extra dependency). Existing env vars win."""
    if not path.is_file():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


@dataclass(frozen=True)
class Config:
    email: str
    password: str
    host: str = "127.0.0.1"
    port: int = 8765
    poll_min_interval: float = 30.0
    device: str | None = None  # name or DeviceID of the unit the app should show by default

    @classmethod
    def load(cls) -> "Config":
        _load_dotenv(Path(__file__).resolve().parents[2] / ".env")
        email = os.environ.get("MELCLOUD_EMAIL", "")
        if not email:
            raise SystemExit("MELCLOUD_EMAIL ist nicht gesetzt (siehe bridge/.env.example).")
        password = os.environ.get("MELCLOUD_PASSWORD") or keyring.get_password(KEYRING_SERVICE, email)
        if not password:
            raise SystemExit("Kein Passwort gefunden. Bitte `climatebridge set-password` ausführen.")
        return cls(
            email=email,
            password=password,
            host=os.environ.get("BRIDGE_HOST", "127.0.0.1"),
            port=int(os.environ.get("BRIDGE_PORT", "8765")),
            poll_min_interval=float(os.environ.get("POLL_MIN_INTERVAL", "30")),
            device=os.environ.get("MELCLOUD_DEVICE", "").strip() or None,
        )
