#!/usr/bin/env bash
# Build rilis. Default: APK. Set TARGET=appbundle untuk .aab (Play Store)
# atau TARGET=ipa untuk iOS.
#   ./scripts/build_prod.sh                 # apk
#   TARGET=appbundle ./scripts/build_prod.sh
#   TARGET=ipa       ./scripts/build_prod.sh
# Konfigurasi server dibaca dari konstanta di lib/core/config/app_config.dart.
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="${TARGET:-apk}"
exec flutter build "$TARGET" \
  --release \
  "$@"
