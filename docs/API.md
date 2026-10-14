# Bridge-API (lokal, `http://127.0.0.1:8765`)

| Methode | Pfad | Beschreibung |
|---|---|---|
| GET | `/health` | `{"ok": true, "version": "0.1.0"}` |
| GET | `/devices` | `[{"id": 123, "name": "Schlafzimmer", "serial": "…", "default": true}]`. `default` = passt zu `MELCLOUD_DEVICE` |
| GET | `/devices/{id}/state[?force=1]` | Vollständiger Status (gecacht ≥ `POLL_MIN_INTERVAL`, `force=1` umgeht das) |
| PATCH | `/devices/{id}/state` | Teil-Update, Antwort = neuer (optimistischer) Status |

## Status-Objekt

```json
{
  "id": 123, "name": "Schlafzimmer", "power": true,
  "room_temperature": 25.0, "outdoor_temperature": null,
  "target_temperature": 21.0, "target_temperature_min": 16.0, "target_temperature_max": 31.0,
  "target_temperature_step": 0.5,
  "operation_mode": "cool", "operation_modes": ["heat", "dry", "cool", "fan_only", "heat_cool"],
  "fan_speed": "auto", "fan_speeds": ["auto", "1", "2", "3", "4", "5"],
  "vane_vertical": "auto", "vane_vertical_positions": ["auto", "1_up", "2", "3", "4", "5_down", "swing"],
  "vane_horizontal": null, "vane_horizontal_positions": [],
  "wifi_signal": -60, "has_error": false, "error_code": null, "last_seen": "2026-10-14T10:40:00"
}
```

## PATCH-Body

Beliebige Teilmenge von `power`, `target_temperature`, `operation_mode`, `fan_speed`,
`vane_vertical`, `vane_horizontal`. Werte werden gegen die Gerätefähigkeiten geprüft:

```bash
curl -X PATCH localhost:8765/devices/123/state -H 'Content-Type: application/json' \
     -d '{"power": true, "target_temperature": 22.5}'
```

Fehler: `404 {"error": "device_not_found"}`, `422 {"error": "invalid_patch", "detail": "…"}`.
