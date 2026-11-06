#!/usr/bin/env bash
# Build rilis. Default: APK. Set TARGET=appbundle untuk .aab (Play Store)
# atau TARGET=ipa untuk iOS.
#   ./scripts/build_prod.sh                 # apk
#   TARGET=appbundle ./scripts/build_prod.sh
#   TARGET=ipa       ./scripts/build_prod.sh
# Build --release otomatis memakai apiHostRilis & makoScanQrBaseUrlRilis dari
# lib/core/config/app_config.dart. Sebelum build, test app_config dijalankan
# supaya alamat rilis yang masih http:// atau IP LAN ditolak.
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="${TARGET:-apk}"

echo "Memeriksa alamat server rilis (test/app_config_test.dart)..."
if ! flutter test test/app_config_test.dart; then
  echo "✗ Alamat rilis di lib/core/config/app_config.dart tidak valid — build dibatalkan." >&2
  exit 1
fi
grep -E "static const String (apiHostRilis|makoScanQrBaseUrlRilis)" lib/core/config/app_config.dart \
  | sed -E "s/.*(apiHostRilis|makoScanQrBaseUrlRilis) = '([^']*)'.*/  ✓ \1 = \2/"

exec flutter build "$TARGET" \
  --release \
  "$@"
