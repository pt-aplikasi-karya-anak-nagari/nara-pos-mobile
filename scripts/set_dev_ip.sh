#!/usr/bin/env bash
# Set apiHostDev (dan makoScanQrBaseUrlDev) di lib/core/config/app_config.dart
# ke IP LAN Mac SAAT INI. Hindari edit manual tiap IP DHCP berubah.
# Nilai ...Rilis tidak disentuh.
# Port API default 3001, web 3000 — override: PORT=xxxx WEB_PORT=yyyy ./scripts/set_dev_ip.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${PORT:-3001}"
WEB_PORT="${WEB_PORT:-3000}"

# Ambil IP LAN aktif (WiFi en0 dulu, lalu en1/ethernet).
IP=""
for iface in en0 en1 en2; do
  IP=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
  [ -n "$IP" ] && break
done
if [ -z "$IP" ]; then
  echo "✗ Gagal mendapatkan IP LAN (en0/en1/en2). Pastikan Mac terhubung WiFi." >&2
  exit 1
fi

HOST="http://$IP:$PORT"
QR="http://$IP:$WEB_PORT/menu"
python3 - "$HOST" "$QR" <<'PY'
import re, sys
host, qr = sys.argv[1], sys.argv[2]
path = "lib/core/config/app_config.dart"
src = open(path).read()
# Ganti HANYA konstanta dev; nilai rilis tetap.
src, n1 = re.subn(r"(static const String apiHostDev\s*=\s*)'[^']*'", r"\g<1>'" + host + "'", src)
src, n2 = re.subn(r"(static const String makoScanQrBaseUrlDev\s*=\s*)'[^']*'", r"\g<1>'" + qr + "'", src)
if n1 == 0:
    raise SystemExit("✗ Konstanta apiHostDev tidak ditemukan di " + path)
open(path, "w").write(src)
print(f"✓ app_config.dart → apiHostDev={host}, makoScanQrBaseUrlDev={qr} (x{n1}, x{n2})")
PY

echo "  Pastikan HP di WiFi yang sama, lalu run ulang: ./scripts/run_dev.sh"
