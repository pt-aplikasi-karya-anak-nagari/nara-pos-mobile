#!/usr/bin/env bash
# Jalankan app dalam environment PROD (backend produksi, TANPA banner).
# ⚠️ Pastikan env/prod.json mengarah ke server https produksi yang benar.
# Pemakaian: ./scripts/run_prod.sh [argumen flutter run tambahan]
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter run \
  --dart-define-from-file=env/prod.json \
  "$@"
