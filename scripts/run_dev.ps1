# Jalankan app mode debug dengan alamat server dari env/dev.json.
# Padanan scripts/run_dev.sh.
#
#   powershell -ExecutionPolicy Bypass -File scripts\run_dev.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\run_dev.ps1 -d RRCRA0220HR
# Argumen tambahan diteruskan ke `flutter run`. IP PC berubah? scripts\set_dev_ip.ps1
Set-Location (Join-Path $PSScriptRoot '..')
. "$PSScriptRoot\_env.ps1"
Confirm-EnvDev
Show-Env 'env/dev.json'
flutter run --dart-define-from-file=env/dev.json @args
exit $LASTEXITCODE
