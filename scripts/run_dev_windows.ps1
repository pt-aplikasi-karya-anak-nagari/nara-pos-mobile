# Jalankan app NARA di HP Android lewat kabel USB (Windows), tanpa Wi-Fi.
#
# `adb reverse` meneruskan port API (3001) & web (3000) di HP ke PC, lalu app
# dijalankan dengan env/usb.json: salinan env/dev.json yang menunjuk ke
# 127.0.0.1. Tidak perlu tahu IP Wi-Fi, dan tidak terpengaruh firewall Windows.
# Bila HP & PC di Wi-Fi yang sama, scripts\run_dev.ps1 biasa sudah cukup.
#
# Pemakaian (dari folder nara_pos_mobile):
#   powershell -ExecutionPolicy Bypass -File scripts\run_dev_windows.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\run_dev_windows.ps1 -d RRCRA0220HR
# Argumen tambahan diteruskan ke `flutter run`.
param([int]$Port = 3001, [int]$WebPort = 3000)
Set-Location (Join-Path $PSScriptRoot '..')
. "$PSScriptRoot\_env.ps1"

foreach ($p in @($Port, $WebPort)) {
  adb reverse "tcp:$p" "tcp:$p"
  if ($LASTEXITCODE -ne 0) { Fail 'adb reverse gagal. Pastikan HP tersambung USB & USB debugging aktif (cek: adb devices).' }
  Ok "adb reverse tcp:$p -> PC:$p"
}

$isi = [ordered]@{
  NARA_API_HOST    = "http://127.0.0.1:$Port"
  NARA_WEB_URL     = "http://127.0.0.1:$WebPort"
  NARA_MENU_QR_URL = "http://127.0.0.1:$WebPort/menu"
}
[IO.File]::WriteAllText((Join-Path (Get-Location) 'env/usb.json'), ($isi | ConvertTo-Json) + "`n", (New-Object Text.UTF8Encoding $false))
Show-Env 'env/usb.json'

flutter run --dart-define-from-file=env/usb.json @args
exit $LASTEXITCODE
