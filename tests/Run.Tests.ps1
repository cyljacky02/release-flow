param([string]$Root = (Join-Path $PSScriptRoot ('../.work/tests-' + [Guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot '../scripts/New-DemoEnvironment.ps1') -Root $Root
$Root = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root))
Import-Module (Join-Path $PSScriptRoot '../src/ReleaseFlow.psm1') -Force
$script:passed = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
    $script:passed++; Write-Host "PASS: $Message"
}
function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $didThrow = $false
    try { & $Action | Out-Null } catch { $didThrow = $true; Write-Host "Expected rejection: $($_.Exception.Message)" }
    Assert-True $didThrow $Message
}
function Get-Version { (Get-Content (Join-Path $production 'bin/version.txt') -Raw).Trim() }
function Make-Plan([string]$Version, [string]$Name) {
    $path = Join-Path $Root "$Name.json"
    New-RfPlan -PackagePath (Join-Path $Root "inbox/node-a/$Version") -TargetConfigPath $config -OutputPath $path | Out-Null
    return $path
}
$config = Join-Path $Root 'node-a.json'
$production = Join-Path $Root 'targets/node-a/production'
$protectedData = (Get-FileHash (Join-Path $production 'data/customer.txt')).Hash
$protectedConfig = (Get-FileHash (Join-Path $production 'config/local.json')).Hash
Assert-Throws { Make-Plan '2.0.0' 'unadopted' } 'Cannot silently adopt a production baseline'
New-RfBaseline -TargetConfigPath $config | Out-Null
Assert-Throws { New-RfBaseline -TargetConfigPath $config } 'Existing baseline cannot be silently re-adopted'
New-RfBaseline -TargetConfigPath (Join-Path $Root 'node-b.json') | Out-Null
$plan = Make-Plan '2.0.0' 'upgrade'
$lockPath = Join-Path $Root 'targets/node-a/state/target.lock'
$exclusiveLock = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try { Assert-Throws { Invoke-RfDeployment -PlanPath $plan -ConfirmExecution } 'Concurrent executor is rejected by target lock' }
finally { $exclusiveLock.Dispose() }
$configBytes = [IO.File]::ReadAllBytes($config)
[IO.File]::AppendAllText($config, "`n")
try { Assert-Throws { Invoke-RfDeployment -PlanPath $plan -ConfirmExecution } 'Config changes invalidate approved plan' }
finally { [IO.File]::WriteAllBytes($config, $configBytes) }
Assert-Throws { Invoke-RfDeployment -PlanPath $plan } 'Apply requires explicit execution confirmation'
Invoke-RfDeployment -PlanPath $plan -ConfirmExecution | Out-Null
$status = Get-RfStatus -TargetConfigPath $config
$runRoot = Join-Path $Root "targets/node-a/state/runs/$($status.CurrentRun.RunId)"
Assert-True (Test-Path (Join-Path $runRoot 'report.json')) 'Structured deployment report generated'
Assert-True (Test-Path (Join-Path $runRoot 'report.txt')) 'Readable deployment report generated'
Assert-True (Test-Path (Join-Path $runRoot 'snapshot.zip')) 'Snapshot archive generated'
Assert-True ($status.Services.worker -and -not $status.Services.optional) 'Originally stopped service stays stopped'
Assert-True ((Get-Version) -eq '2.0.0') 'Upgrade installed target version'
Assert-True (-not (Test-Path (Join-Path $production 'bin/legacy.txt'))) 'Removed file is deleted'
Assert-True (Test-Path (Join-Path $production 'bin/feature.txt')) 'Added file is installed'
Assert-True ((Get-Content (Join-Path $Root 'targets/node-b/production/bin/version.txt') -Raw).Trim() -eq '1.0.0') 'Other target is not modified'
Assert-True ((Get-FileHash (Join-Path $production 'data/customer.txt')).Hash -eq $protectedData) 'Runtime data is preserved'
Assert-True ((Get-FileHash (Join-Path $production 'config/local.json')).Hash -eq $protectedConfig) 'Site configuration is preserved'
$noop = Make-Plan '2.0.0' 'noop'
$runsBefore = @(Get-ChildItem (Join-Path $Root 'targets/node-a/state/runs') -Directory).Count
Invoke-RfDeployment -PlanPath $noop -ConfirmExecution | Out-Null
$runsAfter = @(Get-ChildItem (Join-Path $Root 'targets/node-a/state/runs') -Directory).Count
Assert-True ($runsBefore -eq $runsAfter) 'No-op does not create a backup run'
Assert-Throws { Invoke-RfRecovery -TargetConfigPath $config } 'Recovery requires confirmation'
# Post-deploy drift must not be overwritten by recovery.
$versionPath = Join-Path $production 'bin/version.txt'
$original = [IO.File]::ReadAllBytes($versionPath)
[IO.File]::WriteAllText($versionPath, 'manual-change')
Assert-Throws { Invoke-RfRecovery -TargetConfigPath $config -ConfirmExecution } 'Recovery blocks post-deployment drift'
[IO.File]::WriteAllBytes($versionPath, $original)
Invoke-RfRecovery -TargetConfigPath $config -ConfirmExecution | Out-Null
Assert-True ((Get-Version) -eq '1.0.0') 'Successful upgrade is recoverable'
Assert-True (Test-Path (Join-Path $production 'bin/legacy.txt')) 'Recovery restores deleted file'
Assert-True (-not (Test-Path (Join-Path $production 'bin/feature.txt'))) 'Recovery removes added file'
$plan = Make-Plan '2.0.0' 'upgrade-again'
Invoke-RfDeployment -PlanPath $plan -ConfirmExecution | Out-Null
$down = Make-Plan '1.0.0' 'downgrade'
Invoke-RfDeployment -PlanPath $down -ConfirmExecution | Out-Null
Assert-True ((Get-Version) -eq '1.0.0') 'Downgrade installed older version'
$status = Get-RfStatus -TargetConfigPath $config
$recoveryEntry = Join-Path $Root "targets/node-a/state/runs/$($status.CurrentRun.RunId)/tools/Recover.ps1"
Move-Item (Join-Path $Root 'inbox/node-a') (Join-Path $Root 'inbox/node-a-held')
try { & $recoveryEntry -ConfirmExecution | Out-Null }
finally {
    Move-Item (Join-Path $Root 'inbox/node-a-held') (Join-Path $Root 'inbox/node-a')
    Import-Module (Join-Path $PSScriptRoot '../src/ReleaseFlow.psm1') -Force
}
Assert-True ((Get-Version) -eq '2.0.0') 'Downgrade recovery works without original package'
Assert-Throws { Invoke-RfRecovery -TargetConfigPath $config -ConfirmExecution } 'Cannot traverse historical recovery sets'
# Unexpected current managed content blocks a new plan.
$original = [IO.File]::ReadAllBytes($versionPath)
[IO.File]::WriteAllText($versionPath, 'drift')
Assert-Throws { Make-Plan '1.0.0' 'drift' } 'Planning blocks production drift'
[IO.File]::WriteAllBytes($versionPath, $original)
Assert-Throws { New-RfPlan -PackagePath (Join-Path $Root 'inbox/node-b/1.0.0') -TargetConfigPath $config -OutputPath (Join-Path $Root 'wrong-target.json') } 'Wrong-target package rejected'
# Changing a package after approval must invalidate execution.
$plan = Make-Plan '1.0.0' 'stale-package'
$packageFile = Join-Path $Root 'inbox/node-a/1.0.0/app/bin/version.txt'
$original = [IO.File]::ReadAllBytes($packageFile)
[IO.File]::WriteAllText($packageFile, 'tampered')
Assert-Throws { Invoke-RfDeployment -PlanPath $plan -ConfirmExecution } 'Package changes invalidate approved plan'
[IO.File]::WriteAllBytes($packageFile, $original)
# Production changes after approval also invalidate the plan.
$plan = Make-Plan '1.0.0' 'stale-production'
$original = [IO.File]::ReadAllBytes($versionPath)
[IO.File]::WriteAllText($versionPath, 'changed-after-plan')
Assert-Throws { Invoke-RfDeployment -PlanPath $plan -ConfirmExecution } 'Production changes invalidate approved plan'
[IO.File]::WriteAllBytes($versionPath, $original)
# Fail midway before service start; safe auto-recovery should restore v2.
$plan = Make-Plan '1.0.0' 'file-failure'
try { Invoke-RfDeployment -PlanPath $plan -ConfirmExecution -FailAfterFiles 1 | Out-Null } catch { Write-Host $_.Exception.Message }
Assert-True ((Get-Version) -eq '2.0.0') 'Pre-start file failure restores actual source version'
$plan = Make-Plan '1.0.0' 'health-failure'
Assert-Throws { Invoke-RfDeployment -PlanPath $plan -ConfirmExecution -FailHealthCheck } 'Post-start health failure is reported'
Assert-True ((Get-Version) -eq '1.0.0') 'Health failure does not silently roll back after service start'
Assert-Throws { Make-Plan '2.0.0' 'blocked-pending' } 'Pending failed deployment blocks a new deployment'
Invoke-RfRecovery -TargetConfigPath $config -ConfirmExecution | Out-Null
Assert-True ((Get-Version) -eq '2.0.0') 'Explicit recovery resolves health failure'
# Delivery integrity and traversal defenses.
$zip = Join-Path $Root 'packages/1.0.0/node-a/node-a.zip'
Assert-Throws { & (Join-Path $PSScriptRoot '../scripts/Deliver.ps1') -ArchivePath $zip -ExpectedSha256 ('0' * 64) -DestinationPath (Join-Path $Root 'bad-checksum') } 'Delivery checks the expected archive hash'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$evil = Join-Path $Root 'evil.zip'
$archive = [IO.Compression.ZipFile]::Open($evil, [IO.Compression.ZipArchiveMode]::Create)
try { $null = $archive.CreateEntry('../escape.txt') } finally { $archive.Dispose() }
Assert-Throws { & (Join-Path $PSScriptRoot '../scripts/Deliver.ps1') -ArchivePath $evil -ExpectedSha256 ((Get-FileHash $evil).Hash) -DestinationPath (Join-Path $Root 'evil-delivery') } 'Delivery rejects ZIP traversal'
Assert-True (-not (Test-Path (Join-Path $Root 'escape.txt'))) 'Traversal does not write outside destination'
$collision = Join-Path $Root 'collision.zip'
$archive = [IO.Compression.ZipFile]::Open($collision, [IO.Compression.ZipArchiveMode]::Create)
try {
    $null = $archive.CreateEntry('config/App.json')
    $null = $archive.CreateEntry('config/app.json')
} finally { $archive.Dispose() }
Assert-Throws { & (Join-Path $PSScriptRoot '../scripts/Deliver.ps1') -ArchivePath $collision -ExpectedSha256 ((Get-FileHash $collision).Hash) -DestinationPath (Join-Path $Root 'collision-delivery') } 'Delivery rejects Windows case-colliding archive entries'
# Relative paths must follow PowerShell's location, not the .NET process directory.
$cwd = Join-Path $Root 'cwd-regression'
New-Item -ItemType Directory -Path $cwd | Out-Null
Push-Location $cwd
try {
    & (Join-Path $PSScriptRoot '../scripts/Build.ps1') -Version '2.0.0' -OutputPath 'build'
    & (Join-Path $PSScriptRoot '../scripts/Package.ps1') -BuildPath 'build' -TargetId 'node-a' -TargetFilesPath (Join-Path $Root 'overlays/node-a') -OutputPath 'package'
    $hash = (Get-Content 'package/node-a.zip.sha256' -Raw).Trim()
    & (Join-Path $PSScriptRoot '../scripts/Deliver.ps1') -ArchivePath 'package/node-a.zip' -ExpectedSha256 $hash -DestinationPath 'inbox'
    New-RfManifest -Root 'inbox/app' -OutputPath 'relative-manifest.json' | Out-Null
    Assert-True (Test-Path (Join-Path $cwd 'relative-manifest.json')) 'All stages resolve relative paths against PowerShell location'
} finally { Pop-Location }
$freshDestination = Join-Path $Root 'fresh-process-inbox'
& powershell -NoProfile -File (Join-Path $PSScriptRoot '../scripts/Deliver.ps1') -ArchivePath $zip -ExpectedSha256 ((Get-FileHash $zip).Hash) -DestinationPath $freshDestination
Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $freshDestination 'app/bin/version.txt'))) 'Delivery works in a fresh Windows PowerShell 5.1 process'
Write-Host "All $script:passed assertions passed. Fixtures retained at $Root"
