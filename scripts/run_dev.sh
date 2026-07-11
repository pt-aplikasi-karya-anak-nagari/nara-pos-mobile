#!/usr/bin/env bash
# Jalankan app dalam environment DEV (backend LAN/dev, banner "DEV").
# Flavor dipilih via APP_ENV di env/dev.json (flutter_flavor runtime).
# Selaras dengan backend SERVER_ENVIRONMENT=development & web .env.local.
# Pemakaian: ./scripts/run_dev.sh [argumen flutter run tambahan]
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter run \
  --dart-define-from-file=env/dev.json \
  "$@"
