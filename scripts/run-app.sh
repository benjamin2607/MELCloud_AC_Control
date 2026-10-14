#!/usr/bin/env bash
# Baut und startet die Menubar-App. `--demo` zeigt Beispieldaten ohne Bridge.
set -euo pipefail
cd "$(dirname "$0")/../app"
if [[ "${1:-}" == "--demo" ]]; then export CLIMATE_DEMO=1; fi
exec swift run ClimateControl
