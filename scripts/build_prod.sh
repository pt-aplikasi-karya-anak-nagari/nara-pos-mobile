#!/usr/bin/env bash
# Build rilis. Default: APK. Set TARGET=appbundle untuk .aab (Play Store)
# atau TARGET=ipa untuk iOS.
#   ./scripts/build_prod.sh                 # apk
#   TARGET=appbundle ./scripts/build_prod.sh
#   TARGET=ipa       ./scripts/build_prod.sh
# Alamat server diambil dari env/prod.json (--dart-define-from-file). Sebelum
# build, test app_config dijalankan DENGAN env/prod.json supaya alamat rilis
# yang masih http:// atau IP LAN ditolak.
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

. scripts/_env.sh
echo "Memeriksa alamat server rilis (test/app_config_test.dart + env/prod.json)..."
if ! flutter test test/app_config_test.dart --dart-define-from-file=env/prod.json; then
  echo "✗ Alamat di env/prod.json tidak valid untuk rilis — build dibatalkan." >&2
  exit 1
fi
tampilkan_env env/prod.json

# ── Anti-repackaging: sidik jari sertifikat rilis resmi ─────────────────────
# Aplikasi membandingkan sertifikat penanda tangan APK yang terpasang dengan
# nilai ini; APK yang dibongkar lalu ditandatangani ulang orang lain ditolak
# (lib/core/keamanan/integritas_perangkat.dart). Bisa juga diisi manual lewat
# env NARA_SERTIFIKAT_SHA256 (mis. sidik jari "App signing key" di Play Console
# bila memakai Play App Signing — APK dari Play ditandatangani kunci Google).
SERTIFIKAT="${NARA_SERTIFIKAT_SHA256:-}"
if [ -z "$SERTIFIKAT" ] && [ "$TARGET" = "apk" ] && command -v keytool >/dev/null 2>&1; then
  prop() { grep -E "^$1=" android/key.properties | head -1 | cut -d= -f2- | tr -d '\r'; }
  STORE="$(prop storeFile)"
  case "$STORE" in /*|[A-Za-z]:*) ;; *) STORE="android/app/$STORE" ;; esac
  SERTIFIKAT="$(keytool -list -v -keystore "$STORE" -alias "$(prop keyAlias)" \
    -storepass "$(prop storePassword)" 2>/dev/null \
    | grep -E 'SHA256:' | head -1 | sed -E 's/.*SHA256: *//' | tr -d ': \r' || true)"
fi
if [ -n "$SERTIFIKAT" ]; then
  echo "  ✓ Sertifikat rilis ${SERTIFIKAT:0:12}… — pemeriksaan APK dirakit ulang aktif"
else
  echo "  ⚠ Sidik jari sertifikat tidak ditemukan — pemeriksaan APK dirakit ulang dilewati." >&2
  echo "    Untuk AAB/Play App Signing isi NARA_SERTIFIKAT_SHA256 dari Play Console." >&2
fi

# ── Anti reverse engineering kode Dart ───────────────────────────────────────
# --obfuscate mengacak nama kelas & fungsi Dart di libapp.so. Peta simbol untuk
# membaca stack trace disimpan di build/simbol/<versi> — JANGAN dibagikan;
# unggah ke Sentry (sentry-dart-plugin) supaya laporan crash tetap terbaca.
VERSI="$(grep -E '^version:' pubspec.yaml | sed -E 's/version: *//' | tr -d '\r')"
SIMBOL="build/simbol/${VERSI}"

exec flutter build "$TARGET" \
  --release \
  --obfuscate \
  --split-debug-info="$SIMBOL" \
  --dart-define-from-file=env/prod.json \
  --dart-define=NARA_API_SECRET="$NARA_API_SECRET" \
  --dart-define=NARA_SERTIFIKAT_SHA256="$SERTIFIKAT" \
  "$@"
