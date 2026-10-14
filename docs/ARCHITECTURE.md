# Architecture

```
┌─────────────────────────────── ClimateControl.app ───────────────────────────────┐
│ StatusBarController ── NSStatusItem + borderless NSPanel (SwiftUI PopoverView)   │
│        │                                                                         │
│ ClimateStore (@Observable, @MainActor) ── optimistic UI, debounce, polling       │
│        │                                                                         │
│ MELCloudService (actor) ── token, caches, rate limits ──┐                        │
│        │                                                │                        │
│ AirToAirMapping ── raw JSON ⇄ ACDevice, EffectiveFlags  │ CredentialStore        │
│        │                                                │ (Keychain: token only) │
│ MELCloudAPI ── URLSession (ephemeral), HTTPS            │                        │
└────────┼─────────────────────────────────────────────────────────────────────────┘
         ▼
   https://app.melcloud.com/Mitsubishi.Wifi.Client/
```

## Layers

| File | Responsibility |
|---|---|
| `App/ClimateControlApp.swift` | App entry, settings window, first-run sign-in |
| `App/StatusBarController.swift` | Menu bar item, popover panel (own `NSPanel` because `MenuBarExtra` always draws a square system frame behind the content), context menu |
| `Models/ClimateStore.swift` | UI state. Optimistic updates, one write in flight at a time, no writes while the slider is held |
| `Models/Preferences.swift` | Selected device, hidden modes, launch at login (`SMAppService`) |
| `Services/MELCloudService.swift` | Session handling, device list cache (5 min), state cache (30 s), maps 401 to "sign in again" |
| `Services/AirToAirMapping.swift` | MELCloud codes ⇄ app model, capability detection, input validation |
| `Services/MELCloudAPI.swift` | HTTP requests for `Login/ClientLogin`, `User/ListDevices`, `Device/Get`, `Device/SetAta` |
| `Services/CredentialStore.swift` | Session token in the Keychain, email in UserDefaults |

## MELCloud specifics

- **Writes post the whole state.** `Device/SetAta` expects the full object from `Device/Get` with
  `EffectiveFlags` marking the changed fields (power `0x01`, mode `0x02`, temperature `0x04`, fan `0x08`,
  vertical vane `0x10`). `JSONValue` keeps unknown fields intact through the round trip.
- **Capabilities** come from the device configuration (`CanHeat`, `CanCool`, `NumberOfFanSpeeds`,
  `MinTempHeat` …). The UI only offers what the unit reports. Temperature limits depend on the mode.
- **Vane flags are swapped** in the API: `ModelSupportsVaneHorizontal` describes the up/down vane.
- **Error code 8000** means "no error" and is ignored.
- **Rate limits.** Polling faster than about once a minute can get an account throttled. Hence the caches
  and the debounced writes.

## Design notes

- The colour theme interpolates between a cold and a warm palette based on the setpoint (`Theme.swift`).
  A switched-off unit shows a neutral grey.
- Vane and fan icons are drawn with `Canvas` so the active position or speed can be highlighted
  (`VaneIcon.swift`, `FanSpeedIcon.swift`).
