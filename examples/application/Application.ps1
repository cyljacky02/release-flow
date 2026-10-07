param([switch]$HealthCheck)
$ErrorActionPreference = 'Stop'
if ($HealthCheck) { Write-Output 'Healthy'; exit 0 }
Write-Output ('Release Flow sample version: ' + (Get-Content (Join-Path $PSScriptRoot 'version.txt') -Raw))
