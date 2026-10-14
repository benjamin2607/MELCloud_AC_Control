# ClimateControl

A native macOS menu bar app for Mitsubishi Electric air conditioners connected to **MELCloud**.
Control power, temperature, mode, fan speed and vane position from a compact popover. No browser and
no official app needed.

- Native SwiftUI, a single small app with no dependencies, Python or background server
- The colour theme follows the setpoint, from blue (cool) to amber (warm); airflow animation follows the fan speed
- Multiple indoor units: switch from the popover
- Starts with your Mac (optional)
- The password is never stored; only the MELCloud session token is kept in your Keychain

> **Unofficial.** Not affiliated with or endorsed by Mitsubishi Electric. MELCloud is a trademark of
> Mitsubishi Electric Corporation. The app uses the same web API as the official MELCloud app, which may
> change at any time.

Works with **MELCloud** (app.melcloud.com) air-to-air units such as the MSZ-AY, MSZ-LN and MSZ-EF wall units.
**MELCloud Home** is a different service and is not supported.

## Requirements

- macOS 14 Sonoma or later
- A MELCloud account with at least one air-to-air unit
- To build from source: Swift 5.10+ (Xcode Command Line Tools are enough)

## Installation

### Build from source (recommended)

```bash
git clone https://github.com/benjamin2607/melcloud_macos_popover.git
cd melcloud_macos_popover
scripts/install.sh
```

This builds `ClimateControl.app`, copies it to `/Applications` (or `~/Applications`) and starts it.

### Prebuilt release

Download `ClimateControl.zip` from the [Releases](https://github.com/benjamin2607/melcloud_macos_popover/releases)
page, unzip it and move the app to `/Applications`. The app is ad-hoc signed but **not notarized** by
Apple, so macOS blocks the first launch. To allow it: right-click the app › **Open** › **Open**, or
**System Settings › Privacy & Security › Open Anyway**. Compare the download against the published
SHA-256 checksum first.

## First start

1. Settings open automatically. Sign in with your MELCloud email and password.
2. Pick the unit to show if you have several.
3. Optional: hide modes you never use (e.g. *Cool* in a heating-only setup) under **Shown modes**.

Afterwards:

| Action | How |
|---|---|
| Open the popover | Click the menu bar icon |
| Settings, Quit | Right-click the menu bar icon, or <kbd>⌘</kbd><kbd>,</kbd> while the popover is open |
| Close the popover | Click elsewhere or press <kbd>Esc</kbd> |
| Launch at login | Settings › General (enabled by default for the installed app) |

## How it works

The app talks directly to the MELCloud web API over HTTPS: sign-in, device list, device state, and
writing changes. To stay within MELCloud's rate limits it polls every 60 seconds, caches device data and
bundles rapid changes (such as dragging the slider) into a single request. Changes reach the unit through
the cloud and usually take a few seconds. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Development

```bash
scripts/run-app.sh --demo     # sample data, no account needed
scripts/run-app.sh            # real account (no launch-at-login when run this way)
scripts/build-app.sh          # build/ClimateControl.app
```

- Open in Xcode: `open app/Package.swift`
- Tests: `swift test --package-path app` (needs a full Xcode; the Command Line Tools ship no test framework)
- `CLIMATE_OPEN_ON_LAUNCH=1` opens the popover right after launch, which is handy for layout work
- App icon: `scripts/make-icon.sh` regenerates `app/Resources/AppIcon.icns`

## Security

See [SECURITY.md](SECURITY.md) for how credentials are handled and how to report a vulnerability.

## License

[MIT](LICENSE). The MELCloud protocol handling is based on
[python-melcloud](https://github.com/erwindouna/python-melcloud) (MIT), see [NOTICE](NOTICE).
