"""CLI entry point: `climatebridge` (serve) and `climatebridge set-password`."""

from __future__ import annotations

import argparse
import asyncio
import getpass
import logging

import keyring
from aiohttp import web

from .config import KEYRING_SERVICE, Config
from .melcloud_service import BridgeStartError, MelCloudService
from .server import create_app


def main() -> None:
    parser = argparse.ArgumentParser(prog="climatebridge")
    parser.add_argument("command", nargs="?", default="serve", choices=["serve", "set-password", "list-devices"])
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(levelname)s %(name)s: %(message)s")

    if args.command == "set-password":
        email = input("MELCloud E-Mail: ").strip()
        keyring.set_password(KEYRING_SERVICE, email, getpass.getpass("MELCloud Passwort: "))
        print(f"Passwort für {email} im Schlüsselbund gespeichert. Setze MELCLOUD_EMAIL={email} in bridge/.env.")
        return

    config = Config.load()
    if args.command == "list-devices":
        try:
            asyncio.run(_print_devices(config))
        except BridgeStartError as err:
            raise SystemExit(f"Fehler: {err}") from None
        return

    # Bind to localhost only: the API has no auth (see docs/PLAN.md, Phase 4).
    try:
        web.run_app(create_app(MelCloudService(config)), host=config.host, port=config.port)
    except BridgeStartError as err:
        raise SystemExit(f"Fehler: {err}") from None


async def _print_devices(config: Config) -> None:
    service = MelCloudService(config)
    await service.start()
    try:
        devices = await service.list_devices()
    finally:
        await service.stop()
    print(f"{'ID':>10}  {'Name':<24} Seriennummer")
    for d in devices:
        marker = "  ← MELCLOUD_DEVICE" if d["default"] else ""
        print(f"{d['id']:>10}  {d['name']:<24} {d['serial'] or '–'}{marker}")


if __name__ == "__main__":
    main()
