#!/usr/bin/env bash
# Build rilis. Default: APK. Set TARGET=appbundle untuk .aab (Play Store)
# atau TARGET=ipa untuk iOS.
#   ./scripts/build_prod.sh                 # apk
#   TARGET=appbundle ./scripts/build_prod.sh
#   TARGET=ipa       ./scripts/build_prod.sh
# Build --release otomatis memakai apiHostRilis & makoScanQrBaseUrlRilis dari
# lib/core/config/app_config.dart. Sebelum build, test app_config dijalankan
# supaya alamat rilis yang masih http:// atau IP LAN ditolak.
#
# Wajib env NARA_API_SECRET = API_SECRET_KEY server produksi. Nilainya tidak
# pernah ditulis di repo; disuntik ke app lewat --dart-define.
#   NARA_API_SECRET='...' TARGET=appbundle ./scripts/build_prod.sh
# Android juga butuh android/key.properties (kunci upload) — lihat README.
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="${TARGET:-apk}"

if [ -z "${NARA_API_SECRET:-}" ]; then
  echo "✗ Env NARA_API_SECRET kosong — isi dengan API_SECRET_KEY server produksi." >&2
  exit 1
fi
if [ "$NARA_API_SECRET" = "mako_api_secret_key_789" ] || [ "${#NARA_API_SECRET}" -lt 16 ]; then
  echo "✗ NARA_API_SECRET masih secret dev / kurang dari 16 karakter — server produksi akan menolaknya." >&2
  exit 1
fi
if [ "$TARGET" != "ipa" ] && [ ! -f android/key.properties ]; then
  echo "✗ android/key.properties tidak ada — build rilis Android wajib ditandatangani kunci upload. Lihat README." >&2
  exit 1
fi

echo "Memeriksa alamat server rilis (test/app_config_test.dart)..."
if ! flutter test test/app_config_test.dart; then
  echo "✗ Alamat rilis di lib/core/config/app_config.dart tidak valid — build dibatalkan." >&2
  exit 1
fi
grep -E "static const String (apiHostRilis|makoScanQrBaseUrlRilis)" lib/core/config/app_config.dart \
  | sed -E "s/.*(apiHostRilis|makoScanQrBaseUrlRilis) = '([^']*)'.*/  ✓ \1 = \2/"

exec flutter build "$TARGET" \
  --release \
  --dart-define=NARA_API_SECRET="$NARA_API_SECRET" \
  "$@"
