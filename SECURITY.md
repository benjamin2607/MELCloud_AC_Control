# Security

## How ClimateControl handles your data

| Data | Where it goes |
|---|---|
| MELCloud password | Sent once over HTTPS to `app.melcloud.com` at sign-in. **Never stored**, logged or written to disk. |
| Session token | macOS Keychain, generic password `io.github.benjamin2607.climatecontrol.melcloud`, accessibility *after first unlock, this device only* (not synced via iCloud). Removed on sign-out or when MELCloud rejects it. |
| Email address | UserDefaults (`~/Library/Preferences/io.github.benjamin2607.climatecontrol.plist`), shown in Settings. |
| Device state | Memory only. |

- Network traffic goes **only** to `https://app.melcloud.com`. App Transport Security enforces TLS.
  The URL session is ephemeral, with no cookie store and no disk cache.
- The app opens **no listening ports** and has **no third-party dependencies**.
- Values sent to MELCloud are validated against the unit's reported capabilities
  (`AirToAirMapping.apply`).
- Polling is rate-limited to protect your account from being throttled.
- Release builds are ad-hoc signed with the hardened runtime. They are **not notarized**. Verify the
  SHA-256 checksum published with each release, or build from source.

To remove everything: sign out in Settings (deletes the Keychain item), quit the app, delete it, and
optionally run `defaults delete io.github.benjamin2607.climatecontrol`.

## Reporting a vulnerability

Please do **not** open a public issue. Use GitHub's
[private vulnerability reporting](https://github.com/benjamin2607/melcloud_macos_popover/security/advisories/new)
instead. You will get an answer within a few days.
