"""aiohttp app exposing the bridge API on localhost. See docs/API.md."""

from __future__ import annotations

import json

from aiohttp import web

from . import __version__
from .melcloud_service import DeviceNotFound, MelCloudService
from .models import PatchError

SERVICE = web.AppKey("service", MelCloudService)


def _device_id(request: web.Request) -> int:
    try:
        return int(request.match_info["device_id"])
    except ValueError:
        raise web.HTTPBadRequest(text="device_id muss eine Zahl sein") from None


@web.middleware
async def error_middleware(request: web.Request, handler):
    try:
        return await handler(request)
    except DeviceNotFound:
        return web.json_response({"error": "device_not_found"}, status=404)
    except PatchError as err:
        return web.json_response({"error": "invalid_patch", "detail": str(err)}, status=422)


async def health(_: web.Request) -> web.Response:
    return web.json_response({"ok": True, "version": __version__})


async def list_devices(request: web.Request) -> web.Response:
    return web.json_response(await request.app[SERVICE].list_devices())


async def get_state(request: web.Request) -> web.Response:
    force = request.query.get("force") == "1"
    return web.json_response(await request.app[SERVICE].state(_device_id(request), force=force))


async def patch_state(request: web.Request) -> web.Response:
    try:
        body = await request.json()
    except json.JSONDecodeError:
        raise web.HTTPBadRequest(text="Ungültiges JSON") from None
    return web.json_response(await request.app[SERVICE].apply(_device_id(request), body))


def create_app(service: MelCloudService) -> web.Application:
    app = web.Application(middlewares=[error_middleware])
    app[SERVICE] = service
    app.router.add_get("/health", health)
    app.router.add_get("/devices", list_devices)
    app.router.add_get("/devices/{device_id}/state", get_state)
    app.router.add_patch("/devices/{device_id}/state", patch_state)

    async def lifecycle(app: web.Application):
        await service.start()
        yield
        await service.stop()

    app.cleanup_ctx.append(lifecycle)
    return app
