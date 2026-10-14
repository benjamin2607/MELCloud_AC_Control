"""Serialization and validation between pymelcloud's AtaDevice and the bridge JSON API."""

from __future__ import annotations

from typing import Any

from pymelcloud import AtaDevice

WRITABLE_KEYS = {
    "power",
    "target_temperature",
    "operation_mode",
    "fan_speed",
    "vane_vertical",
    "vane_horizontal",
}


class PatchError(ValueError):
    """Raised when a state patch from the app is invalid."""


def matches_device(device: AtaDevice, selector: str | None) -> bool:
    """True if selector is the device's numeric ID or its name (case-insensitive)."""
    if not selector:
        return False
    return selector == str(device.device_id) or selector.casefold() == (device.name or "").casefold()


def serialize(device: AtaDevice, overlay: dict[str, Any] | None = None) -> dict[str, Any]:
    """Flatten an AtaDevice into the JSON shape documented in docs/API.md."""
    state: dict[str, Any] = {
        "id": device.device_id,
        "name": device.name,
        "power": device.power,
        "room_temperature": device.room_temperature,
        "outdoor_temperature": device.outdoor_temperature if device.has_outdoor_temperature else None,
        "target_temperature": device.target_temperature,
        "target_temperature_min": device.target_temperature_min,
        "target_temperature_max": device.target_temperature_max,
        "target_temperature_step": device.target_temperature_step,
        "operation_mode": device.operation_mode,
        "operation_modes": device.operation_modes,
        "fan_speed": device.fan_speed,
        "fan_speeds": device.fan_speeds or [],
        "vane_vertical": device.vane_vertical,
        "vane_vertical_positions": device.vane_vertical_positions or [],
        "vane_horizontal": device.vane_horizontal,
        "vane_horizontal_positions": device.vane_horizontal_positions or [],
        "wifi_signal": device.wifi_signal,
        "has_error": device.has_error,
        # MELCloud reports 8000 ("no error") even when healthy; only expose real errors, always as text.
        "error_code": str(device.error_code) if device.has_error and device.error_code is not None else None,
        "last_seen": device.last_seen.isoformat() if device.last_seen else None,
    }
    if overlay:
        state.update(overlay)
    return state


def validate_patch(device: AtaDevice, patch: Any) -> dict[str, Any]:
    """Check a patch against the device's capabilities before sending it to MELCloud."""
    if not isinstance(patch, dict) or not patch:
        raise PatchError("Body muss ein nicht-leeres JSON-Objekt sein.")
    unknown = set(patch) - WRITABLE_KEYS
    if unknown:
        raise PatchError(f"Unbekannte Felder: {', '.join(sorted(unknown))}")

    clean: dict[str, Any] = {}
    for key, value in patch.items():
        if key == "power":
            if not isinstance(value, bool):
                raise PatchError("power muss bool sein.")
        elif key == "target_temperature":
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                raise PatchError("target_temperature muss eine Zahl sein.")
            lo, hi = device.target_temperature_min, device.target_temperature_max
            if lo is not None and hi is not None and not lo <= value <= hi:
                raise PatchError(f"target_temperature muss zwischen {lo} und {hi} liegen.")
            value = device.round_temperature(float(value))
        else:
            allowed = {
                "operation_mode": device.operation_modes,
                "fan_speed": device.fan_speeds,
                "vane_vertical": device.vane_vertical_positions,
                "vane_horizontal": device.vane_horizontal_positions,
            }[key] or []
            if value not in allowed:
                raise PatchError(f"{key}={value!r} nicht unterstützt. Erlaubt: {allowed}")
        clean[key] = value
    return clean
