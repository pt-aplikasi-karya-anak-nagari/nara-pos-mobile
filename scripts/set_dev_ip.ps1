# Isi env/dev.json dengan IP Wi-Fi/Ethernet PC SAAT INI (API :3001, web :3000).
# Padanan scripts/set_dev_ip.sh.
#
#   powershell -ExecutionPolicy Bypass -File scripts\set_dev_ip.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\set_dev_ip.ps1 -Ip 192.168.1.30 -Port 3005
#
# Adaptor virtual (vEthernet/WSL/Hyper-V/VirtualBox, 172.x) dilewati: tablet
# tidak bisa menjangkaunya.
param([string]$Ip = '', [int]$Port = 3001, [int]$WebPort = 3000)
Set-Location (Join-Path $PSScriptRoot '..')
. "$PSScriptRoot\_env.ps1"

if (-not $Ip) {
  $kandidat = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
      $_.IPAddress -match '^(192\.168|10)\.' -and
      $_.InterfaceAlias -notmatch 'vEthernet|WSL|Hyper-V|VirtualBox|VMware|Loopback'
    } |
    Sort-Object { if ($_.InterfaceAlias -match 'Wi-?Fi|WLAN') { 0 } else { 1 } }
  $Ip = ($kandidat | Select-Object -First 1).IPAddress
}
if (-not $Ip) { Fail 'Gagal mendapatkan IP LAN. Isi manual: scripts\set_dev_ip.ps1 -Ip 192.168.x.x' }

$isi = [ordered]@{
  NARA_API_HOST    = "http://${Ip}:$Port"
  NARA_WEB_URL     = "http://${Ip}:$WebPort"
  NARA_MENU_QR_URL = "http://${Ip}:$WebPort/menu"
}
# Tanpa BOM: flutter membaca berkas ini sebagai JSON.
$json = $isi | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path (Get-Location) 'env/dev.json'), $json + "`n", (New-Object Text.UTF8Encoding $false))
Ok "env/dev.json -> API http://${Ip}:$Port, web http://${Ip}:$WebPort"
Write-Host '  Pastikan HP/tablet di Wi-Fi yang sama, lalu: scripts\run_dev.ps1'
