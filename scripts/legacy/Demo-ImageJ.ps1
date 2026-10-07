param(
    [Parameter(Mandatory=$true)][string]$SourcesRoot,
    [Parameter(Mandatory=$true)][string]$BuildPath,
    [Parameter(Mandatory=$true)][string]$Root
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$SourcesRoot = Get-LegacyAbsolute $SourcesRoot
$BuildPath = Get-LegacyAbsolute $BuildPath
$Root = Get-LegacyAbsolute $Root
Assert-LegacyDisjoint -OutputRoot $Root -InputRoots @($BuildPath, (Join-Path $SourcesRoot 'imagej-extracted'), (Join-Path $SourcesRoot 'exist-source-subset'))
if (Test-Path -LiteralPath $Root) { throw 'Use a new isolated deployment exercise root.' }
$repo = Get-LegacyAbsolute (Join-Path $PSScriptRoot '../..')
$acquisition = Get-Content (Join-Path $SourcesRoot 'acquisition.json') -Raw | ConvertFrom-Json
$attempt = Get-Content (Join-Path $BuildPath 'build-attempt.json') -Raw | ConvertFrom-Json
if ($attempt.Status -ne 'Compiled' -or -not (Test-Path (Join-Path $BuildPath 'app/plugins/JavaScriptEvaluator.class'))) { throw 'A successful real-source plugin build is required.' }
Import-Module (Join-Path $repo 'src/ReleaseFlow.psm1') -Force
New-Item -ItemType Directory -Path $Root | Out-Null
$script:assertions = @()
function Check([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "Legacy exercise assertion failed: $Name" }
    $script:assertions += $Name
    Write-Host "PASS: $Name"
}
function InventoryDigest([string]$Path,[string]$Name) {
    $manifest = Join-Path $Root "$Name-manifest.json"
    New-RfManifest -Root $Path -OutputPath $manifest | Out-Null
    return (Get-FileHash $manifest).Hash
}
foreach ($target in @('legacy-node-a','legacy-node-b')) {
    $production = Join-Path $Root "$target/production"
    $state = Join-Path $Root "$target/state"
    New-Item -ItemType Directory -Path $production -Force | Out-Null
    Copy-Item (Join-Path $BuildPath 'app/classes') $production -Recurse
    New-Item -ItemType Directory -Path (Join-Path $production 'plugins'),(Join-Path $production 'deployment'),(Join-Path $production 'data') -Force | Out-Null
    # A genuine retired loose class from the pinned upstream tree, never loaded or executed.
    Copy-Item (Join-Path $acquisition.ImageJSourcePath 'plugins/MacAdapter.class') (Join-Path $production 'plugins/MacAdapter.class')
    'Synthetic protected runtime data; no real user data' | Set-Content (Join-Path $production 'data/preserve.txt') -Encoding UTF8
    @{TargetId=$target;Scope='Synthetic deployment metadata, not an ImageJ app setting';Phase='baseline'} | ConvertTo-Json | Set-Content (Join-Path $production 'deployment/target.json') -Encoding UTF8
    $before = InventoryDigest $production "$target-before"
    $config = @{SchemaVersion=1;TargetId=$target;ProductionPath=$production;StatePath=$state;ManagedPaths=@('classes','plugins','deployment');ProtectedPaths=@('data');ServiceMode='Simulated';Services=@(@{Name='fixture-worker';InitiallyRunning=$true});StopOrder=@('fixture-worker');StartOrder=@('fixture-worker');HealthCheck=@{Mode='Simulated';Fail=$false}}
    $configPath = Join-Path $Root "$target.json"
    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
    $overlay = Join-Path $Root "$target/overlay"
    New-Item -ItemType Directory -Path (Join-Path $overlay 'deployment') -Force | Out-Null
    @{TargetId=$target;Scope='Synthetic deployment metadata, not an ImageJ app setting';Phase='updated'} | ConvertTo-Json | Set-Content (Join-Path $overlay 'deployment/target.json') -Encoding UTF8
    $packageOutput = Join-Path $Root "$target/package"
    & (Join-Path $repo 'scripts/Package.ps1') -BuildPath $BuildPath -TargetId $target -TargetFilesPath $overlay -OutputPath $packageOutput
    $zip = Join-Path $packageOutput "$target.zip"
    $inbox = Join-Path $Root "$target/inbox"
    & (Join-Path $repo 'scripts/Deliver.ps1') -ArchivePath $zip -ExpectedSha256 ((Get-Content "$zip.sha256" -Raw).Trim()) -DestinationPath $inbox
    $targetManifest = Get-Content (Join-Path $inbox 'manifest.json') -Raw | ConvertFrom-Json
    Check (@($targetManifest.Files | Where-Object { $_.Path -like '*.jar' }).Count -eq 0) "$target transports loose classes without rebuilding a JAR"
    Check (@(Get-ChildItem (Join-Path $inbox 'app') -Filter '*.class' -File -Recurse).Count -eq $attempt.ClassCount) "$target package contains all compiled classes"
    $targetMetadata = Get-Content (Join-Path $inbox 'app/deployment/target.json') -Raw | ConvertFrom-Json
    Check ($targetMetadata.TargetId -ceq $target) "$target receives only its metadata"
    New-RfBaseline -TargetConfigPath $configPath | Out-Null
    $planPath = Join-Path $Root "$target-plan.json"
    $plan = New-RfPlan -PackagePath $inbox -TargetConfigPath $configPath -OutputPath $planPath
    Check (@($plan.Changes | Where-Object { $_.Path -eq 'plugins/JavaScriptEvaluator.class' -and $_.Kind -eq 'Added' }).Count -eq 1) "$target plans genuine separately compiled plugin addition"
    Check (@($plan.Changes | Where-Object { $_.Path -eq 'plugins/MacAdapter.class' -and $_.Kind -eq 'Removed' }).Count -eq 1) "$target plans retired genuine class removal"
    Invoke-RfDeployment -PlanPath $planPath -ConfirmExecution | Out-Null
    Check (Test-Path (Join-Path $production 'plugins/JavaScriptEvaluator.class')) "$target applies loose plugin file"
    Check (-not (Test-Path (Join-Path $production 'plugins/MacAdapter.class'))) "$target removes stale managed class"
    $actualHash = (Get-FileHash (Join-Path $production 'plugins/JavaScriptEvaluator.class')).Hash
    $buildHash = (Get-FileHash (Join-Path $BuildPath 'app/plugins/JavaScriptEvaluator.class')).Hash
    Check ($actualHash -eq $buildHash) "$target plugin bytes match genuine compiler output"
    $status = Get-RfStatus -TargetConfigPath $configPath
    $recovery = Join-Path $state "runs/$($status.CurrentRun.RunId)/tools/Recover.ps1"
    Move-Item $inbox "$inbox-held"
    try { & $recovery -ConfirmExecution | Out-Null }
    finally { Move-Item "$inbox-held" $inbox; Import-Module (Join-Path $repo 'src/ReleaseFlow.psm1') -Force }
    $after = InventoryDigest $production "$target-after"
    Check ($before -eq $after) "$target recovery restores byte-exact initial fixture without original inbox"
}
$report = @{SchemaVersion=1;Project='ImageJ 1.51u';BuildClassCount=$attempt.ClassCount;Assertions=$script:assertions;AssertionCount=$script:assertions.Count;Scope='Genuine compiled upstream files; synthetic two-target deployment topology, metadata and simulated services';UpstreamApplicationExecuted=$false;PluginExecuted=$false;RealServicesOperated=$false;Result='Passed'}
$report | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $Root 'exercise-results.json') -Encoding UTF8
Write-Host "All $($script:assertions.Count) legacy file-deployment assertions passed. No upstream application or plugin executed."
