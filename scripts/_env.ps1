# Dipakai skrip PowerShell lain (dot-source). Padanan scripts/_env.sh.
$ErrorActionPreference = 'Stop'

function Ok($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [X]  $m" -ForegroundColor Red; exit 1 }

# Pastikan env/dev.json ada; dibuat dari env/dev.example.json bila belum.
function Confirm-EnvDev {
  if (-not (Test-Path 'env/dev.json')) {
    Copy-Item 'env/dev.example.json' 'env/dev.json'
    Warn 'env/dev.json dibuat dari env/dev.example.json.'
    Warn 'Isi IP PC Anda: powershell -ExecutionPolicy Bypass -File scripts\set_dev_ip.ps1'
  }
}

function Show-Env($path) {
  Write-Host "Memakai ${path}:"
  $j = Get-Content $path -Raw | ConvertFrom-Json
  foreach ($p in $j.PSObject.Properties) { Write-Host "  $($p.Name) = $($p.Value)" }
}

# Jalankan perintah eksternal; berhenti bila kodenya bukan 0.
function Invoke-Checked {
  param([string]$Exe, [string[]]$Argv, [string]$Pesan)
  & $Exe @Argv
  if ($LASTEXITCODE -ne 0) { Fail $Pesan }
}
