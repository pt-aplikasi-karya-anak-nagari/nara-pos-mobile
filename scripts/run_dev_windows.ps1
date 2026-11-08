# Jalankan app NARA di HP Android lewat kabel USB (Windows).
#
# `adb reverse` meneruskan port 3001 di HP ke port 3001 di PC. Pakai ini bila
# apiHostDev = http://127.0.0.1:3001 (lihat lib/core/config/app_config.dart):
# tidak perlu tahu IP Wi-Fi, dan tidak terpengaruh firewall Windows.
# Bila apiHostDev memakai IP LAN PC, `flutter run` biasa sudah cukup.
#
# Pemakaian (dari folder nara_pos_mobile):
#   powershell -ExecutionPolicy Bypass -File scripts\run_dev_windows.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\run_dev_windows.ps1 -d RRCRA0220HR
# Argumen tambahan diteruskan ke `flutter run`.

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$port = 3001
adb reverse "tcp:$port" "tcp:$port"
if ($LASTEXITCODE -ne 0) { Write-Error "adb reverse gagal. Pastikan HP tersambung USB & USB debugging aktif (cek: adb devices)." }
Write-Host "OK  adb reverse tcp:$port -> PC:$port"

flutter run @args
