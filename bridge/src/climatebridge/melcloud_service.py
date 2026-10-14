"""Owns the MELCloud session, token and device list; rate-limits status polling."""

from __future__ import annotations

import logging
import ssl
import time
from datetime import timedelta
from typing import Any

import aiohttp
import pymelcloud
import truststore
from pymelcloud import DEVICE_TYPE_ATA, AtaDevice

from .config import TOKEN_PATH, Config
from .models import matches_device, serialize, validate_patch

log = logging.getLogger(__name__)


class DeviceNotFound(KeyError):
    pass


class BridgeStartError(RuntimeError):
    """Startup failure with a message meant for the user, not a traceback."""


class MelCloudService:
    def __init__(self, config: Config) -> None:
        self._config = config
        self._session: aiohttp.ClientSession | None = None
        self._devices: dict[int, AtaDevice] = {}
        self._last_update: dict[int, float] = {}

    async def start(self) -> None:
        # Verify certificates against the macOS trust store instead of Python's (often missing) CA bundle.
        tls = truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        self._session = aiohttp.ClientSession(connector=aiohttp.TCPConnector(ssl=tls))
        try:
            await self._connect()
        except BaseException:
            await self.stop()
            raise

    async def _connect(self) -> None:
        token = TOKEN_PATH.read_text().strip() if TOKEN_PATH.is_file() else None
        try:
            await self._load_devices(token or await self._login())
        except aiohttp.ClientResponseError as err:
            if err.status != 401 or token is None:
                raise
            log.info("Gespeicherter Token abgelaufen – neuer Login.")
            await self._load_devices(await self._login())
        except aiohttp.ClientConnectorError as err:
            raise BridgeStartError(f"MELCloud nicht erreichbar: {err}") from err
        log.info("MELCloud verbunden: %s", ", ".join(d.name for d in self._devices.values()) or "keine Geräte")
        selector = self._config.device
        if selector and not any(matches_device(d, selector) for d in self._devices.values()):
            log.warning("MELCLOUD_DEVICE=%r passt zu keinem Gerät – `climatebridge list-devices` zeigt alle.", selector)

    async def stop(self) -> None:
        if self._session and not self._session.closed:
            await self._session.close()

    async def _login(self) -> str:
        try:
            token = await pymelcloud.login(self._config.email, self._config.password, session=self._session)
        except AttributeError:
            # MELCloud answers a failed login with HTTP 200 and LoginData=null, which pymelcloud trips over.
            raise BridgeStartError("MELCloud-Login fehlgeschlagen – E-Mail oder Passwort falsch?") from None
        if not token:
            raise BridgeStartError("MELCloud-Login fehlgeschlagen – E-Mail oder Passwort falsch?")
        TOKEN_PATH.parent.mkdir(parents=True, exist_ok=True)
        TOKEN_PATH.write_text(token)
        TOKEN_PATH.chmod(0o600)
        return token

    async def _load_devices(self, token: str) -> None:
        devices = await pymelcloud.get_devices(
            token,
            self._session,
            conf_update_interval=timedelta(minutes=5),
            device_set_debounce=timedelta(milliseconds=500),
        )
        self._devices = {d.device_id: d for d in devices[DEVICE_TYPE_ATA]}
        self._last_update.clear()

    def _get(self, device_id: int) -> AtaDevice:
        try:
            return self._devices[device_id]
        except KeyError:
            raise DeviceNotFound(device_id) from None

    async def _refresh(self, device: AtaDevice, force: bool = False) -> None:
        last = self._last_update.get(device.device_id, 0.0)
        if not force and time.monotonic() - last < self._config.poll_min_interval:
            return
        await device.update()
        self._last_update[device.device_id] = time.monotonic()

    async def list_devices(self) -> list[dict[str, Any]]:
        return [
            {
                "id": d.device_id,
                "name": d.name,
                "serial": d.serial,
                "default": matches_device(d, self._config.device),
            }
            for d in self._devices.values()
        ]

    async def state(self, device_id: int, force: bool = False) -> dict[str, Any]:
        device = self._get(device_id)
        await self._refresh(device, force)
        return serialize(device)

    async def apply(self, device_id: int, patch: Any) -> dict[str, Any]:
        device = self._get(device_id)
        await self._refresh(device)  # set() needs a fetched state
        clean = validate_patch(device, patch)
        # pymelcloud debounces and writes in the background; answer optimistically.
        await device.set(clean)
        return serialize(device, overlay=clean)
