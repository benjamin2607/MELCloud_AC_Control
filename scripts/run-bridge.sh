#!/usr/bin/env bash
# Startet die Python-Bridge (legt beim ersten Mal das venv an).
set -euo pipefail
cd "$(dirname "$0")/../bridge"
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
  .venv/bin/pip install -q -e ".[dev]"
fi
exec .venv/bin/climatebridge "$@"
