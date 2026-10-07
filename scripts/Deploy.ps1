param(
    [ValidateSet('Menu','Baseline','Plan','Apply','Recover','Status')][string]$Action = 'Menu',
    [Parameter(Mandatory=$true)][string]$TargetConfigPath,
    [string]$PackagePath,
    [string]$PlanPath,
    [switch]$ConfirmExecution
)
$ErrorActionPreference = 'Stop'
$TargetConfigPath = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetConfigPath))
if ($PackagePath) { $PackagePath = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PackagePath)) }
if ($PlanPath) { $PlanPath = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PlanPath)) }
$module = Join-Path $PSScriptRoot 'ReleaseFlow.psm1'
if (-not (Test-Path $module)) { $module = Join-Path $PSScriptRoot '../src/ReleaseFlow.psm1' }
Import-Module $module -Force
if ($Action -eq 'Menu') {
    Write-Host 'Release Flow | simulated-service MVP'
    Write-Host '1. Inspect status  2. Generate plan  3. Execute approved plan  4. Recover latest operation'
    switch (Read-Host 'Select') {
        '1' { $Action = 'Status' }
        '2' { $Action = 'Plan' }
        '3' { $Action = 'Apply' }
        '4' { $Action = 'Recover' }
        default { throw 'No valid action selected.' }
    }
    if ($Action -in @('Apply','Recover')) {
        if ($PlanPath -and (Test-Path $PlanPath) -and $Action -eq 'Apply') { Get-Content $PlanPath -Raw | Write-Host }
        $target = Get-Content $TargetConfigPath -Raw | ConvertFrom-Json
        $answer = Read-Host "Confirm previously approved $Action for target '$($target.TargetId)' by typing its TargetId"
        if ($answer -cne $target.TargetId) { throw 'Execution not confirmed.' }
        $ConfirmExecution = $true
    }
}
switch ($Action) {
    'Baseline' {
        if (-not $ConfirmExecution) { throw 'Baseline adoption requires explicit confirmation of external review.' }
        New-RfBaseline -TargetConfigPath $TargetConfigPath
    }
    'Plan' {
        if (-not $PackagePath -or -not $PlanPath) { throw 'Plan requires PackagePath and PlanPath.' }
        New-RfPlan -PackagePath $PackagePath -TargetConfigPath $TargetConfigPath -OutputPath $PlanPath
        Get-Content $PlanPath -Raw | Write-Host
    }
    'Apply' {
        if (-not $PlanPath) { throw 'Apply requires PlanPath.' }
        $approved = Get-Content $PlanPath -Raw | ConvertFrom-Json
        $suppliedConfig = [IO.Path]::GetFullPath($TargetConfigPath)
        if (-not $approved.TargetConfigPath -or [IO.Path]::GetFullPath($approved.TargetConfigPath) -ne $suppliedConfig) {
            throw 'The approved plan belongs to a different target configuration.'
        }
        Invoke-RfDeployment -PlanPath $PlanPath -ConfirmExecution:$ConfirmExecution
    }
    'Recover' { Invoke-RfRecovery -TargetConfigPath $TargetConfigPath -ConfirmExecution:$ConfirmExecution }
    'Status' { Get-RfStatus -TargetConfigPath $TargetConfigPath }
}
