# Jalankan app mode release terhadap server PRODUKSI (env/prod.json).
# Padanan scripts/run_prod.sh. Wajib env NARA_API_SECRET.
#
#   $env:NARA_API_SECRET = '...'
#   powershell -ExecutionPolicy Bypass -File scripts\run_prod.ps1 [argumen flutter run]
Set-Location (Join-Path $PSScriptRoot '..')
. "$PSScriptRoot\_env.ps1"
if (-not $env:NARA_API_SECRET) { Fail 'Env NARA_API_SECRET kosong - isi dengan API_SECRET_KEY server produksi.' }
Show-Env 'env/prod.json'
flutter run --release --dart-define-from-file=env/prod.json "--dart-define=NARA_API_SECRET=$($env:NARA_API_SECRET)" @args
exit $LASTEXITCODE
