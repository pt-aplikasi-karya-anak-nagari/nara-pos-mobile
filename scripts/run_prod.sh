#!/usr/bin/env bash
# Jalankan app dalam mode release (tanpa banner debug).
# Konfigurasi server dibaca dari konstanta di lib/core/config/app_config.dart.
# Pemakaian: ./scripts/run_prod.sh [argumen flutter run tambahan]
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter run --release "$@"
