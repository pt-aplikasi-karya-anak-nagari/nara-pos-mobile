#!/usr/bin/env bash
# Isi env/dev.json dengan IP LAN PC SAAT INI (API :3001, web :3000).
# Override port: PORT=3005 WEB_PORT=3001 ./scripts/set_dev_ip.sh
# Atau tentukan IP sendiri: IP=192.168.1.30 ./scripts/set_dev_ip.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${PORT:-3001}"
WEB_PORT="${WEB_PORT:-3000}"
IP="${IP:-}"

if [ -z "$IP" ] && command -v ipconfig >/dev/null 2>&1; then
  # macOS: Wi-Fi en0 dulu, lalu en1/ethernet.
  for iface in en0 en1 en2; do
    IP=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    [ -n "$IP" ] && break
  done
fi
if [ -z "$IP" ] && command -v hostname >/dev/null 2>&1; then
  # Linux.
  IP=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^(192\.168|10)\.' | head -1 || true)
fi
if [ -z "$IP" ]; then
  echo "✗ Gagal mendapatkan IP LAN. Isi manual: IP=192.168.x.x ./scripts/set_dev_ip.sh" >&2
  echo "  (Windows: powershell -ExecutionPolicy Bypass -File scripts\set_dev_ip.ps1)" >&2
  exit 1
fi

cat > env/dev.json <<JSON
{
  "NARA_API_HOST": "http://$IP:$PORT",
  "NARA_WEB_URL": "http://$IP:$WEB_PORT",
  "NARA_MENU_QR_URL": "http://$IP:$WEB_PORT/menu"
}
JSON
echo "✓ env/dev.json → API http://$IP:$PORT, web http://$IP:$WEB_PORT"
echo "  Pastikan HP/tablet di Wi-Fi yang sama, lalu: ./scripts/run_dev.sh"
