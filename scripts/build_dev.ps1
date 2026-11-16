# Build APK DEV (debug) yang menunjuk ke server dev di env/dev.json - untuk
# dibagikan ke penguji di jaringan yang sama. Bukan untuk Play Store.
# Padanan scripts/build_dev.sh.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build_dev.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\build_dev.ps1 --split-per-abi
Set-Location (Join-Path $PSScriptRoot '..')
. "$PSScriptRoot\_env.ps1"
Confirm-EnvDev
Show-Env 'env/dev.json'
Invoke-Checked flutter (@('build', 'apk', '--debug', '--dart-define-from-file=env/dev.json') + $args) 'Build APK dev gagal'
Ok 'APK dev: build\app\outputs\flutter-apk\'
