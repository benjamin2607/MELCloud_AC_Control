from types import SimpleNamespace

import pytest

from climatebridge.models import PatchError, validate_patch


def fake_device(**overrides):
    base = dict(
        target_temperature_min=16.0,
        target_temperature_max=31.0,
        operation_modes=["heat", "dry", "cool", "fan_only", "heat_cool"],
        fan_speeds=["auto", "1", "2", "3", "4", "5"],
        vane_vertical_positions=["auto", "1_up", "2", "3", "4", "5_down", "swing"],
        vane_horizontal_positions=[],
        round_temperature=lambda t: round(t * 2) / 2,
    )
    base.update(overrides)
    return SimpleNamespace(**base)


def test_valid_patch_is_rounded():
    assert validate_patch(fake_device(), {"target_temperature": 21.3, "power": True}) == {
        "target_temperature": 21.5,
        "power": True,
    }


@pytest.mark.parametrize(
    "patch",
    [{}, {"foo": 1}, {"power": "on"}, {"target_temperature": 40}, {"operation_mode": "turbo"}],
)
def test_invalid_patches(patch):
    with pytest.raises(PatchError):
        validate_patch(fake_device(), patch)


@pytest.mark.parametrize(
    ("selector", "expected"),
    [("123", True), ("wohnzimmer", True), ("Wohnzimmer ", False), ("", False), (None, False), ("124", False)],
)
def test_matches_device(selector, expected):
    from climatebridge.models import matches_device

    assert matches_device(SimpleNamespace(device_id=123, name="Wohnzimmer"), selector) is expected
