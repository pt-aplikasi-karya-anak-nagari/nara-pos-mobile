#!/usr/bin/env bash
# Build rilis PRODUKSI. Default: APK. Set TARGET=appbundle untuk .aab (Play Store)
# atau TARGET=ipa untuk iOS.
#   ./scripts/build_prod.sh                 # apk
#   TARGET=appbundle ./scripts/build_prod.sh
#   TARGET=ipa       ./scripts/build_prod.sh
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="${TARGET:-apk}"
exec flutter build "$TARGET" \
  --release \
  --dart-define-from-file=env/prod.json \
  "$@"
