# ClimateControl – Umsetzungsplan

Custom macOS-Menubar-Popover für eine Mitsubishi Electric **MSZ-AY20VGK** (Wandgerät, integriertes WLAN) über **MELCloud** (nicht MELCloud Home).

## 1. Architektur

```
┌──────────────────────────┐   HTTP/JSON (127.0.0.1:8765)   ┌───────────────────────────┐   HTTPS   ┌──────────┐
│  app/  SwiftUI           │ ─────────────────────────────▶ │ bridge/  Python (aiohttp) │ ────────▶ │ MELCloud │
│  NSStatusItem + NSPanel  │ ◀───────────────────────────── │ python-melcloud           │ ◀──────── │  Cloud   │
└──────────────────────────┘                                └───────────────────────────┘           └──────────┘
```

* **UI: Swift + SwiftUI** – eigenes `NSStatusItem` mit randlosem, transparentem `NSPanel`, Inhalt in SwiftUI
  (`StatusBarController.swift`). `MenuBarExtra(.window)` wurde verworfen: macOS zeichnet dort immer einen
  eckigeren Systemrahmen hinter den Inhalt, der sich nicht sauber entfernen lässt. Native Animationen (`TimelineView`, `Canvas`, `contentTransition(.numericText)`),
  Materialien, Dark Mode und geringer Ressourcenverbrauch. Electron/Tauri wären deutlich schwerer und
  fühlen sich nie ganz nativ an, für ein Menüleisten-Widget ist SwiftUI deshalb die beste Wahl.
* **API: Python-Bridge mit `python-melcloud`** (Import-Name `pymelcloud`, der von Home Assistant genutzte
  Fork von `pymelcloud`). Die Bridge kapselt Login, Token, Rate-Limits und Validierung und bietet der App
  eine schlanke REST-API (siehe [API.md](API.md)).
* **Warum zweigeteilt?** Die gewünschte Library ist Python. So bleibt die App „dumm“, und die
  MELCloud-Logik lässt sich separat im Terminal testen. Später optional: Bridge nach Swift portieren
  (die MELCloud-API besteht im Kern aus nur ~4 Endpunkten), damit nur noch eine App ausgeliefert wird.

## 2. Gerätefähigkeiten (MSZ-AY20VGK über MELCloud)

| Funktion | MELCloud-Feld | UI |
|---|---|---|
| Ein/Aus | `power` | Power-Button |
| Solltemperatur (meist 16–31 °C, 0,5er-Schritte) | `target_temperature` | Großanzeige + Slider |
| Raumtemperatur | `room_temperature` | Header |
| Modus Heizen/Lüften/Auto (Kühlen/Entfeuchten bewusst ausgeblendet, `OperationMode.selectable`) | `operation_mode` | Kachel „Modus“ |
| Lüfter Auto + Stufen 1–5 | `fan_speed` | Kachel „Lüfter“ |
| Vertikale Lamelle Auto/1–5/Swing | `vane_vertical` | Kachel „Lamelle“ mit Winkel-Icons (`VaneIcon.swift`) |
| Horizontale Lamelle | `vane_horizontal` | **keine Kachel**: wird beim MSZ-AY von Hand verstellt, obwohl MELCloud Positionen meldet |

Die App zeigt **nur Optionen an, die die Bridge vom Gerät meldet**, nichts ist fest verdrahtet.
„Eco Mode“ und „Sleep“ aus der Vorlage gibt es in der MELCloud-ATA-API nicht direkt, sie werden
deshalb weggelassen (siehe Phase 3 für mögliche Ersatzfunktionen).

## 3. Design-Konzept (nach Vorlage)

* Dunkles, abgerundetes Panel, **Hintergrund interpoliert zwischen Blau (16 °C) und Bernstein (31 °C)**
  (`Theme.swift`, Wert `ACDevice.warmth` 0…1). **Ausgeschaltet: durchgehend grau**, inkl. Slider.
* Stilisierte Inneneinheit mit **animiertem Luftstrom**, Geschwindigkeit folgt der Lüfterstufe
  und wird bei „Aus“ ausgeblendet.
* Große Temperaturanzeige mit Zahl-Animation, Gradient-Slider mit −/+.
* Drei Kacheln (Modus · Lüfter · Lamelle) mit Auswahl-Popover.
* Menüleiste: Icon + Solltemperatur, wenn eingeschaltet.

## 4. Phasen

### Phase 0 – Setup ✅ (dieser Stand)
- [x] Ordnerstruktur, SwiftPM-Paket, Python-Paket
- [x] Bridge: Login, Token-Cache, Geräte, Status, Patch + Validierung
- [x] App: Popover-Grundgerüst, Theme, Slider, Kacheln, Airflow-Animation, Demo-Modus
- [x] `.gitignore` vorbereitet

### Phase 1 – Erster Echtbetrieb
- [ ] `climatebridge set-password` + `.env` anlegen, Bridge gegen das echte Gerät testen (`curl`)
- [ ] Feldwerte des MSZ-AY20VGK prüfen (Temperaturbereich, Lüfterstufen, horizontale Lamelle?)
- [ ] Fehlerfälle: Token abgelaufen während des Betriebs (401 → Re-Login), MELCloud down, Gerät offline
- [ ] `git init`, erster Commit, privates Repo (z. B. GitHub)

### Phase 2 – Ein-Klick-Start
- [ ] App startet die Bridge selbst als Child-Prozess (oder `launchd`-LaunchAgent in `~/Library/LaunchAgents`)
- [ ] Richtiges App-Bundle (`.app` mit `Info.plist`, `LSUIElement = YES`, Icon) via Xcode-Projekt oder Build-Skript
- [ ] „Bei Anmeldung starten“ (`SMAppService.mainApp`)

### Phase 3 – Komfort & Feinschliff
- [x] Geräteauswahl bei mehreren Innengeräten (`MELCLOUD_DEVICE` + Menü im Popover)
- [ ] Einstellungsfenster (E-Mail, Poll-Intervall, Bridge-Port)
- [ ] Schnell-Presets („Nacht 20 °C, Lüfter 1“) als Ersatz für Sleep/Eco
- [ ] Energieverbrauch/Tagesstatistik (`total_energy_consumed`, falls das Gerät es meldet)
- [ ] Haptik/Sound beim Einrasten, Tastaturkürzel (↑/↓ für Temperatur)
- [ ] Außentemperatur, WLAN-Signal, Fehlercode-Anzeige

### Phase 4 – Qualität
- [ ] CI (GitHub Actions: `pytest`, `swift build`)
- [ ] Bridge absichern: zufälliges Shared-Secret im Schlüsselbund, als Header von der App mitgeschickt
- [ ] Optional: Bridge nach Swift portieren → eine einzelne, signierte App

## 5. Rahmenbedingungen & Risiken

* **Rate-Limits:** MELCloud drosselt bei zu häufigen Abfragen. Die App pollt alle 60 s, die Bridge
  fragt höchstens alle 30 s (`POLL_MIN_INTERVAL`) an. Schreibbefehle werden in App (600 ms) und
  Bridge (500 ms) gebündelt, damit ein Slider-Zug nur **einen** Request erzeugt.
* **Latenz:** Änderungen erreichen das Gerät über die Cloud mit einigen Sekunden Verzögerung. Die UI
  aktualisiert sich deshalb sofort (optimistisch) und gleicht danach ab.
* **Inoffizielle API:** MELCloud kann sich ändern. Die Kapselung in der Bridge begrenzt den Schaden.
* **Secrets:** Passwort im macOS-Schlüsselbund, Token in `~/Library/Application Support/ClimateControl`
  (chmod 600). `.env` steht in `.gitignore`.
