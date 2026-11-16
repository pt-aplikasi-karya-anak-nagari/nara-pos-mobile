#!/usr/bin/env bash
# Jalankan app mode debug dengan alamat server dari env/dev.json.
#   ./scripts/run_dev.sh                 # perangkat pilihan flutter
#   ./scripts/run_dev.sh -d <device-id>  # argumen lain diteruskan ke flutter run
# IP PC berubah? ./scripts/set_dev_ip.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
pastikan_env_dev
tampilkan_env env/dev.json
exec flutter run --dart-define-from-file=env/dev.json "$@"
