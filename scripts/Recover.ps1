param(
    [string]$TargetConfigPath = (Join-Path $PSScriptRoot 'target-config.json'),
    [switch]$ConfirmExecution
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ReleaseFlow.psm1') -Force
Invoke-RfRecovery -TargetConfigPath $TargetConfigPath -ConfirmExecution:$ConfirmExecution
