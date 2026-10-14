#!/usr/bin/env bash
# Builds ClimateControl.app, installs it to /Applications (or ~/Applications) and starts it.
# On first start the app registers itself to launch at login (can be turned off in Settings).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh

dest="/Applications"
if [[ ! -w "$dest" ]]; then
  dest="$HOME/Applications"
  mkdir -p "$dest"
fi

# Quit a running copy so the new build replaces it cleanly.
osascript -e 'tell application id "io.github.benjamin2607.climatecontrol" to quit' >/dev/null 2>&1 || true
sleep 1

rm -rf "$dest/ClimateControl.app"
cp -R build/ClimateControl.app "$dest/"
open "$dest/ClimateControl.app"
echo "Installed to $dest/ClimateControl.app"
