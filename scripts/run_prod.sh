#!/usr/bin/env bash
# Jalankan app mode release terhadap server PRODUKSI (env/prod.json).
# Wajib env NARA_API_SECRET (= API_SECRET_KEY server produksi).
#   NARA_API_SECRET='...' ./scripts/run_prod.sh [argumen flutter run]
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
if [ -z "${NARA_API_SECRET:-}" ]; then
  echo "✗ Env NARA_API_SECRET kosong — isi dengan API_SECRET_KEY server produksi." >&2
  exit 1
fi
tampilkan_env env/prod.json
exec flutter run --release \
  --dart-define-from-file=env/prod.json \
  --dart-define=NARA_API_SECRET="$NARA_API_SECRET" "$@"
