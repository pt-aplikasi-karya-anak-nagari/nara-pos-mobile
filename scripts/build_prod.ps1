# Build rilis untuk Windows. Padanan scripts/build_prod.sh.
#
#   $env:NARA_API_SECRET = '<API_SECRET_KEY server produksi>'
#   powershell -ExecutionPolicy Bypass -File scripts\build_prod.ps1                    # APK
#   powershell -ExecutionPolicy Bypass -File scripts\build_prod.ps1 -Target appbundle  # Play Store
#
# Alamat server diambil dari env/prod.json dan diperiksa dulu (https, bukan IP
# lokal). Android wajib android/key.properties (kunci upload) - lihat README.
# Opsional: $env:NARA_SERTIFIKAT_SHA256 (sidik jari "App signing key" Play
# Console bila memakai Play App Signing). Argumen lain diteruskan ke flutter build.
param([ValidateSet('apk', 'appbundle', 'ipa')][string]$Target = 'apk')
Set-Location (Join-Path $PSScriptRoot '..')
. "$PSScriptRoot\_env.ps1"

$secret = $env:NARA_API_SECRET
if (-not $secret) { Fail 'Env NARA_API_SECRET kosong - isi dengan API_SECRET_KEY server produksi.' }
if ($secret -eq 'mako_api_secret_key_789' -or $secret.Length -lt 16) {
  Fail 'NARA_API_SECRET masih secret dev / kurang dari 16 karakter - server produksi akan menolaknya.'
}
if ($Target -ne 'ipa' -and -not (Test-Path 'android/key.properties')) {
  Fail 'android/key.properties tidak ada - build rilis Android wajib ditandatangani kunci upload. Lihat README.'
}

Write-Host 'Memeriksa alamat server rilis (test/app_config_test.dart + env/prod.json)...'
Invoke-Checked flutter @('test', 'test/app_config_test.dart', '--dart-define-from-file=env/prod.json') `
  'Alamat di env/prod.json tidak valid untuk rilis - build dibatalkan.'
Show-Env 'env/prod.json'

# Anti-repackaging: sidik jari sertifikat rilis resmi (lihat build_prod.sh).
$sertifikat = $env:NARA_SERTIFIKAT_SHA256
if (-not $sertifikat -and $Target -eq 'apk' -and (Get-Command keytool -ErrorAction SilentlyContinue)) {
  $prop = @{}
  Get-Content 'android/key.properties' | ForEach-Object {
    if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)$') { $prop[$Matches[1]] = $Matches[2].Trim() }
  }
  $store = $prop['storeFile']
  if ($store -and -not [IO.Path]::IsPathRooted($store)) { $store = Join-Path 'android/app' $store }
  $baris = keytool -list -v -keystore $store -alias $prop['keyAlias'] -storepass $prop['storePassword'] 2>$null |
    Select-String 'SHA256:' | Select-Object -First 1
  if ($baris) { $sertifikat = (($baris.Line -replace '.*SHA256:\s*', '') -replace '[:\s]', '') }
}
if ($sertifikat) {
  Ok "Sertifikat rilis $($sertifikat.Substring(0, [Math]::Min(12, $sertifikat.Length)))... - pemeriksaan APK dirakit ulang aktif"
} else {
  Warn 'Sidik jari sertifikat tidak ditemukan - pemeriksaan APK dirakit ulang dilewati.'
  Warn 'Untuk AAB/Play App Signing isi $env:NARA_SERTIFIKAT_SHA256 dari Play Console.'
}

# Anti reverse engineering: --obfuscate + peta simbol di build/simbol/<versi>
# (JANGAN dibagikan; unggah ke Sentry).
$versi = ((Get-Content 'pubspec.yaml' | Select-String '^version:' | Select-Object -First 1).Line -replace 'version:\s*', '').Trim()
$simbol = "build/simbol/$versi"

Invoke-Checked flutter (@(
    'build', $Target, '--release', '--obfuscate', "--split-debug-info=$simbol",
    '--dart-define-from-file=env/prod.json',
    "--dart-define=NARA_API_SECRET=$secret",
    "--dart-define=NARA_SERTIFIKAT_SHA256=$sertifikat"
  ) + $args) 'Build rilis gagal'
Ok "Build rilis $Target selesai (versi $versi)"
