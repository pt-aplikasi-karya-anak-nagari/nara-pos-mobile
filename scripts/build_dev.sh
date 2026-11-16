#!/usr/bin/env bash
# Build APK DEV (debug) yang menunjuk ke server dev di env/dev.json — untuk
# dibagikan ke penguji di jaringan yang sama. Bukan untuk Play Store.
#   ./scripts/build_dev.sh               # build/app/outputs/flutter-apk/app-debug.apk
#   ./scripts/build_dev.sh --split-per-abi
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
pastikan_env_dev
tampilkan_env env/dev.json
flutter build apk --debug --dart-define-from-file=env/dev.json "$@"
echo "✓ APK dev: build/app/outputs/flutter-apk/"
