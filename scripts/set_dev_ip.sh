#!/usr/bin/env bash
# Set apiHost (dan makoScanQrBaseUrl) di lib/core/config/app_config.dart ke IP
# LAN Mac SAAT INI. Hindari edit manual tiap IP DHCP berubah.
# Port default 3001 — override: PORT=xxxx ./scripts/set_dev_ip.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${PORT:-3001}"

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
python3 - "$HOST" <<'PY'
import re, sys
host = sys.argv[1]
path = "lib/core/config/app_config.dart"
src = open(path).read()
# Ganti nilai konstanta apiHost dan makoScanQrBaseUrl (host dev = sama saat LAN).
src, n1 = re.subn(r"(static const String apiHost\s*=\s*)'[^']*'", r"\g<1>'" + host + "'", src)
src, n2 = re.subn(r"(static const String makoScanQrBaseUrl\s*=\s*)'[^']*'", r"\g<1>'" + host + "'", src)
if n1 == 0:
    raise SystemExit("✗ Konstanta apiHost tidak ditemukan di " + path)
open(path, "w").write(src)
print(f"✓ app_config.dart → apiHost={host} (apiHost x{n1}, makoScanQrBaseUrl x{n2})")
PY

echo "  Pastikan HP di WiFi yang sama, lalu run ulang: ./scripts/run_dev.sh"
