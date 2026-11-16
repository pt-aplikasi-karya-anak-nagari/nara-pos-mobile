#!/usr/bin/env bash
# Jalankan app dalam mode release (tanpa banner debug).
# Konfigurasi server dibaca dari konstanta di lib/core/config/app_config.dart.
# Mode release wajib env NARA_API_SECRET (= API_SECRET_KEY server tujuan);
# tanpa itu app menolak start.
# Pemakaian: NARA_API_SECRET='...' ./scripts/run_prod.sh [argumen flutter run tambahan]
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${NARA_API_SECRET:-}" ]; then
  echo "✗ Env NARA_API_SECRET kosong — isi dengan API_SECRET_KEY server tujuan." >&2
  exit 1
fi
exec flutter run --release --dart-define=NARA_API_SECRET="$NARA_API_SECRET" "$@"
