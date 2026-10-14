# ClimateControl

Native macOS-Menüleisten-Steuerung für Mitsubishi-Electric-Klimageräte über MELCloud.
SwiftUI-Popover + lokale Python-Bridge auf Basis von [`python-melcloud`](https://github.com/erwindouna/python-melcloud).

```
app/        SwiftUI Menubar-App (Swift Package, macOS 14+)
bridge/     Python-Bridge: MELCloud ↔ lokale REST-API
docs/       PLAN.md (Roadmap & Architektur), API.md (Bridge-Schnittstelle)
scripts/    run-bridge.sh, run-app.sh
prototype/  Design-Experimente
```

## Einrichtung

### 1. Zugangsdaten hinterlegen

Es werden dieselben Zugangsdaten wie in der MELCloud-App verwendet.

```bash
cp bridge/.env.example bridge/.env
open -e bridge/.env                 # MELCLOUD_EMAIL=deine@mail.de eintragen
scripts/run-bridge.sh set-password  # fragt E-Mail + Passwort ab → macOS-Schlüsselbund
```

* Das **Passwort** liegt im Schlüsselbund (Eintrag `climatecontrol-melcloud`, sichtbar in
  „Schlüsselbundverwaltung“), nicht in einer Datei. Ändern: Befehl einfach erneut ausführen.
* Alternativ (nicht empfohlen) `MELCLOUD_PASSWORD=…` in `bridge/.env`. Die Datei ist per `.gitignore` geschützt.
* Nach dem ersten Login merkt sich die Bridge einen Token unter
  `~/Library/Application Support/ClimateControl/melcloud.token`. Löschen erzwingt einen neuen Login.

### 2. Gerät auswählen

```bash
scripts/run-bridge.sh list-devices
```

```
        ID  Name                     Seriennummer
  12345678  Wohnzimmer               1234567890
  12345679  Schlafzimmer             1234567891
```

Den **Namen** (wie in der MELCloud-App, Groß-/Kleinschreibung egal) oder die **ID** in `bridge/.env` eintragen:

```
MELCLOUD_DEVICE=Schlafzimmer
```

Die ID ist robuster, falls du Geräte in der MELCloud-App umbenennst. In der App kannst du außerdem
jederzeit über den **Gerätenamen rechts neben der Temperatur** wechseln. Diese Auswahl wird gespeichert
und hat Vorrang vor `MELCLOUD_DEVICE`. Reihenfolge: Auswahl im Popover → `MELCLOUD_DEVICE` → erstes Gerät.
Auswahl zurücksetzen: `defaults delete ClimateControl selectedDeviceID`.

### 3. Starten

```bash
scripts/run-bridge.sh        # Terminal 1 – muss laufen, solange die App genutzt wird
scripts/run-app.sh           # Terminal 2 – oder: scripts/run-app.sh --demo (ohne MELCloud)
```

Test ohne App: `curl localhost:8765/devices`

## Entwicklung

* Bridge-Tests: `cd bridge && .venv/bin/pytest`
* App bauen: `cd app && swift build`. In Xcode öffnen: `open app/Package.swift`
* App-Tests (`swift test`) brauchen ein vollständiges **Xcode** (die Command Line Tools enthalten kein Test-Framework).
