#!/usr/bin/env bash
# Set API host di env/dev.json ke IP LAN Mac SAAT INI. Hindari edit manual tiap
# IP DHCP berubah. Port default 3001 — override: PORT=xxxx ./scripts/set_dev_ip.sh
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
import json, sys
host = sys.argv[1]
path = "env/dev.json"
d = json.load(open(path))
d["API_HOST"] = host
# Base URL menu QR umumnya di host yang sama saat dev.
if "MAKO_SCAN_QR_BASE_URL" in d:
    d["MAKO_SCAN_QR_BASE_URL"] = host
if "NARA_SCAN_QR_BASE_URL" in d:
    d["NARA_SCAN_QR_BASE_URL"] = host
with open(path, "w") as f:
    json.dump(d, f, indent=2); f.write("\n")
print(f"✓ env/dev.json → API_HOST={host}")
PY

echo "  Pastikan HP di WiFi yang sama, lalu run ulang: ./scripts/run_dev.sh"
