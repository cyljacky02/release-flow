param([string]$Root = (Join-Path $PSScriptRoot ('../.work/demo-' + [Guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'New-DemoEnvironment.ps1') -Root $Root
$Root = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root))
Import-Module (Join-Path $PSScriptRoot '../src/ReleaseFlow.psm1') -Force
foreach ($target in @('node-a','node-b')) {
    $config = Join-Path $Root "$target.json"
    New-RfBaseline -TargetConfigPath $config | Out-Null
    $plan = Join-Path $Root "$target-upgrade.json"
    New-RfPlan -PackagePath (Join-Path $Root "inbox/$target/2.0.0") -TargetConfigPath $config -OutputPath $plan | Out-Null
    Write-Host "DEMO ONLY: programmatically confirm approved upgrade for $target"
    Invoke-RfDeployment -PlanPath $plan -ConfirmExecution | Format-List | Out-Host
}
$config = Join-Path $Root 'node-a.json'
Write-Host 'Recover successful upgrade: node-a goes back to its actual version-1 baseline.'
Invoke-RfRecovery -TargetConfigPath $config -ConfirmExecution | Format-List | Out-Host
# Reapply v2, then demonstrate that a downgrade can itself be undone to v2.
$up = Join-Path $Root 'node-a-upgrade-again.json'
New-RfPlan -PackagePath (Join-Path $Root 'inbox/node-a/2.0.0') -TargetConfigPath $config -OutputPath $up | Out-Null
Invoke-RfDeployment -PlanPath $up -ConfirmExecution | Out-Null
$down = Join-Path $Root 'node-a-downgrade.json'
New-RfPlan -PackagePath (Join-Path $Root 'inbox/node-a/1.0.0') -TargetConfigPath $config -OutputPath $down | Out-Null
Invoke-RfDeployment -PlanPath $down -ConfirmExecution | Out-Null
Invoke-RfRecovery -TargetConfigPath $config -ConfirmExecution | Format-List | Out-Host
Write-Host "Demo completed. node-a and node-b both have version 2. Inspect preserved artifacts: $Root"
