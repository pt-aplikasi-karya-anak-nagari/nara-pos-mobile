#!/usr/bin/env bash
# Jalankan app dalam mode debug.
# Konfigurasi server dibaca dari konstanta di lib/core/config/app_config.dart
# (bukan lagi env / --dart-define). Untuk dev di LAN, set IP dulu:
#   ./scripts/set_dev_ip.sh
# Pemakaian: ./scripts/run_dev.sh [argumen flutter run tambahan]
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter run "$@"
