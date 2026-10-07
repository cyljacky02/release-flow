# Dependency-free Windows PowerShell 5.1 interruption/data-safety regression tests.
# Run: powershell.exe -NoProfile -File tests/Interruption.Tests.ps1
# Fixtures/logs are retained for diagnosis. No real services or external systems are used.
param([string]$Root = (Join-Path $PSScriptRoot ('../.work/interruption-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root))
if (Test-Path -LiteralPath $Root) { throw 'Test root must be a fresh directory; existing content will not be reset.' }
$modulePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../src/ReleaseFlow.psm1'))
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
Import-Module $modulePath -Force
# Fail early if running against a core that does not yet implement the reviewed APIs.
foreach ($entry in @(
    @{ Name='Get-RfToolVersion'; Parameters=@() },
    @{ Name='Invoke-RfDeployment'; Parameters=@('FailServiceStop','FailServiceStart','PauseAfterFiles','PauseSignalPath') },
    @{ Name='Invoke-RfRecovery'; Parameters=@('FailAfterFiles','PauseAfterFiles','PauseSignalPath') }
)) {
    $command = Get-Command $entry.Name -ErrorAction Stop
    foreach ($name in $entry.Parameters) {
        if (-not $command.Parameters.ContainsKey($name)) { throw "Core API not ready: $($entry.Name) -$name" }
    }
}
[void][IO.Directory]::CreateDirectory($Root)
$script:passed = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
    $script:passed++; Write-Host "PASS: $Message"
}
function Assert-Rejected([scriptblock]$Action, [string]$Message, [string]$Pattern = 'RF_') {
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_ }
    Assert-True ($null -ne $failure -and [string]$failure -match $Pattern) "$Message (expected $Pattern; got $failure)"
}
function Write-TestText([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Get-TestInventory([string]$Path) {
    return (@(Get-ChildItem -LiteralPath $Path -File -Recurse -Force | ForEach-Object {
        $relative = $_.FullName.Substring($Path.Length + 1).Replace('\','/')
        '{0}|{1}|{2}' -f $relative, $_.Length, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    } | Sort-Object) -join "`n")
}
function Get-TestCanonicalJson($Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [Collections.IDictionary]) {
        $parts=@(); foreach($key in @($Value.Keys | Sort-Object)) { $parts += (ConvertTo-Json ([string]$key) -Compress) + ':' + (Get-TestCanonicalJson $Value[$key]) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [pscustomobject]) {
        $map=@{}; foreach($property in $Value.PSObject.Properties) { $map[$property.Name]=$property.Value }
        return Get-TestCanonicalJson $map
    }
    if ($Value -is [array]) { $parts=@();foreach($entry in $Value){$parts += Get-TestCanonicalJson $entry};return '[' + ($parts -join ',') + ']' }
    return ConvertTo-Json $Value -Compress
}
function New-TestFixture([string]$Name) {
    $fixtureRoot = Join-Path $Root $Name
    $production = Join-Path $fixtureRoot 'production'
    $package = Join-Path $fixtureRoot 'package'
    $state = Join-Path $fixtureRoot 'state'
    $config = Join-Path $fixtureRoot 'target.json'
    Write-TestText (Join-Path $production 'bin/version.txt') '1.0.0'
    Write-TestText (Join-Path $production 'bin/worker.txt') 'old worker'
    Write-TestText (Join-Path $production 'bin/legacy.txt') 'restore this removed file'
    Write-TestText (Join-Path $production 'data/customer.txt') 'site-owned customer data'
    Write-TestText (Join-Path $package 'app/bin/version.txt') '2.0.0'
    Write-TestText (Join-Path $package 'app/bin/worker.txt') 'new worker'
    Write-TestText (Join-Path $package 'app/bin/zz-added.txt') 'remove this added file on recovery'
    # Keep the synthetic package self-contained without invoking Build/Package or git.
    $tools = Join-Path $package 'tools'
    [void][IO.Directory]::CreateDirectory($tools)
    Copy-Item -LiteralPath $modulePath -Destination $tools
    foreach ($name in @('Deploy.ps1','Recover.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "../scripts/$name") -Destination $tools
    }
    $metadata = @{ SchemaVersion=1; TargetId='interruption-test'; Version='2.0.0'; Commit='synthetic'; ToolVersion=(Get-RfToolVersion) }
    Write-TestText (Join-Path $package 'package.json') ($metadata | ConvertTo-Json -Depth 12)
    New-RfManifest -Root (Join-Path $package 'app') -OutputPath (Join-Path $package 'manifest.json') | Out-Null
    $definition = @{
        SchemaVersion=1; TargetId='interruption-test'; ProductionPath=$production; StatePath=$state
        ManagedPaths=@('bin'); ProtectedPaths=@('data'); ServiceMode='Simulated'
        Services=@(@{Name='worker';InitiallyRunning=$true},@{Name='optional';InitiallyRunning=$false})
        StopOrder=@('worker','optional'); StartOrder=@('optional','worker')
        HealthCheck=@{Mode='Simulated';Fail=$false}
    }
    Write-TestText $config ($definition | ConvertTo-Json -Depth 12)
    New-RfBaseline -TargetConfigPath $config | Out-Null
    $plan = Join-Path $fixtureRoot 'approved-plan.json'
    New-RfPlan -PackagePath $package -TargetConfigPath $config -OutputPath $plan | Out-Null
    return [pscustomobject]@{
        Home=$fixtureRoot; Production=$production; Package=$package; State=$state; Config=$config; Plan=$plan
        Before=(Get-TestInventory $production); BaselineHash=(Get-FileHash -LiteralPath (Join-Path $state 'baseline.json')).Hash
        BaselineCanonical=(Get-TestCanonicalJson (Get-Content (Join-Path $state 'baseline.json') -Raw | ConvertFrom-Json))
    }
}
function Assert-InitialServices($Status, [string]$Label) {
    Assert-True ($Status.Services.worker -eq $true -and $Status.Services.optional -eq $false) "$Label restores initially running/stopped simulated services"
}
function Assert-Pending($Fixture, [string]$ExpectedStatus, [string]$Label) {
    $status = Get-RfStatus -TargetConfigPath $Fixture.Config
    Assert-True ($null -ne $status.CurrentRun -and $status.CurrentRun.Status -eq $ExpectedStatus) "$Label has precise journal status $ExpectedStatus"
    $pending = @($status.PendingRuns)
    Assert-True ($pending.Count -eq 1 -and $pending[0].RunId -eq $status.CurrentRun.RunId -and $pending[0].Status -eq $ExpectedStatus) "$Label exposes exactly this unfinished run in PendingRuns"
    return $status
}
function Assert-Blocked($Fixture, [string]$Label) {
    $before = Get-TestInventory $Fixture.Production
    $baseline = (Get-FileHash -LiteralPath (Join-Path $Fixture.State 'baseline.json')).Hash
    Assert-Rejected {
        New-RfPlan -PackagePath $Fixture.Package -TargetConfigPath $Fixture.Config -OutputPath (Join-Path $Fixture.Home 'blocked-plan.json')
    } "$Label blocks planning for an unfinished run" 'RF_IncompleteRun:'
    Assert-Rejected { Invoke-RfDeployment -PlanPath $Fixture.Plan -ConfirmExecution } "$Label blocks execution of an already approved plan" 'RF_IncompleteRun:'
    Assert-True ((Get-TestInventory $Fixture.Production) -ceq $before) "$Label rejected actions do not mutate production"
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $Fixture.State 'baseline.json')).Hash -eq $baseline) "$Label rejected actions do not mutate baseline"
}
function Assert-Recovered($Fixture, [string]$Label) {
    $status = Get-RfStatus -TargetConfigPath $Fixture.Config
    Assert-True ((Get-TestInventory $Fixture.Production) -ceq $Fixture.Before) "$Label restores exact before inventory (paths, lengths and SHA256, including protected data)"
    Assert-True ($status.CurrentRun.Status -eq 'Recovered' -and @($status.PendingRuns).Count -eq 0) "$Label commits Recovered and clears PendingRuns"
    Assert-True ((Get-TestCanonicalJson (Get-Content (Join-Path $Fixture.State 'baseline.json') -Raw | ConvertFrom-Json)) -ceq $Fixture.BaselineCanonical) "$Label restores all adopted baseline fields and inventory"
    Assert-InitialServices $status $Label
    New-RfPlan -PackagePath $Fixture.Package -TargetConfigPath $Fixture.Config -OutputPath (Join-Path $Fixture.Home 'retry-plan.json') | Out-Null
    Assert-True (Test-Path -LiteralPath (Join-Path $Fixture.Home 'retry-plan.json')) "$Label permits a fresh plan"
}
function Assert-OperationFile($Fixture, $Operation, [string]$Side, [string]$Label) {
    $path = Join-Path $Fixture.Production $Operation.Path
    $expected = $Operation[$Side]
    if ($null -eq $expected) {
        Assert-True (-not (Test-Path -LiteralPath $path)) "$Label matches journal $Side absence for $($Operation.Path)"
    } else {
        Assert-True ((Test-Path -LiteralPath $path -PathType Leaf) -and
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $expected.Sha256 -and
            (Get-Item -LiteralPath $path).Length -eq $expected.Length) "$Label matches journal $Side hash/length for $($Operation.Path)"
    }
}
function Invoke-KilledChild($Fixture, [ValidateSet('Deploy','Recover')][string]$Mode) {
    # Marker is a fresh sibling outside production, state and package, never a managed file.
    $marker = Join-Path $Fixture.Home ($Mode + '-paused.signal')
    Assert-True (-not (Test-Path -LiteralPath $marker)) "$Mode marker is initially absent"
    $childPath = Join-Path $Fixture.Home ($Mode + '-child.ps1')
    $quotedModule = $modulePath.Replace("'", "''")
    $quotedMarker = $marker.Replace("'", "''")
    if ($Mode -eq 'Deploy') {
        $path = $Fixture.Plan.Replace("'", "''")
        $call = "Invoke-RfDeployment -PlanPath '$path' -ConfirmExecution -PauseAfterFiles 1 -PauseSignalPath '$quotedMarker'"
    } else {
        $path = $Fixture.Config.Replace("'", "''")
        $call = "Invoke-RfRecovery -TargetConfigPath '$path' -ConfirmExecution -PauseAfterFiles 1 -PauseSignalPath '$quotedMarker'"
    }
    Write-TestText $childPath ("`$ErrorActionPreference = 'Stop'`r`nImport-Module '$quotedModule' -Force`r`n$call | Out-Null`r`n")
    $stdout = Join-Path $Fixture.Home ($Mode + '-stdout.log')
    $stderr = Join-Path $Fixture.Home ($Mode + '-stderr.log')
    $arguments = '-NoProfile -NonInteractive -File "' + $childPath + '"'
    $process = Start-Process -FilePath $powershell -ArgumentList $arguments -PassThru -WorkingDirectory $Fixture.Home -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        while (-not (Test-Path -LiteralPath $marker)) {
            $process.Refresh()
            if ($process.HasExited) { throw "$Mode child exited before pause marker (exit $($process.ExitCode)); inspect $stderr" }
            if ($clock.Elapsed.TotalSeconds -ge 20) { throw "$Mode child did not signal within 20 seconds; inspect $stdout and $stderr" }
            Start-Sleep -Milliseconds 50
        }
        $process.Refresh()
        Assert-True (-not $process.HasExited) "$Mode child is blocked at explicit durable pause marker"
        $process.Kill()
        Assert-True ($process.WaitForExit(5000)) "$Mode child terminates after forced process kill"
    } finally {
        $clock.Stop()
        $process.Refresh()
        if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(5000) }
        $process.Dispose()
    }
}

# Kill deployment after its first durably recorded file operation; no automatic cleanup runs.
$f = New-TestFixture 'deployment-killed'
Invoke-KilledChild $f 'Deploy'
$s = Assert-Pending $f 'Applying' 'Killed deployment'
Assert-True ($s.CurrentRun.BackupsComplete -and -not $s.CurrentRun.StartupAttempted) 'Killed deployment has completed backups but has not attempted startup'
$done = @($s.CurrentRun.Operations | Where-Object { $_.State -eq 'Done' })
Assert-True ($done.Count -eq 1) 'Exactly one deployment operation is durably Done'
foreach ($op in $s.CurrentRun.Operations) {
    $side = 'Before'; if ($op.State -eq 'Done') { $side = 'After' }
    Assert-OperationFile $f $op $side 'Killed deployment'
}
Assert-True ((Get-TestInventory $f.Production) -cne $f.Before -and -not $s.Services.worker) 'Killed deployment leaves actual partial file changes and simulated worker stopped'
Assert-Blocked $f 'Killed deployment'
Invoke-RfRecovery -TargetConfigPath $f.Config -ConfirmExecution | Out-Null
Assert-Recovered $f 'Killed deployment recovery'

# Interrupt explicit recovery after the first restored file and safely resume it.
$f = New-TestFixture 'recovery-killed'
Invoke-RfDeployment -PlanPath $f.Plan -ConfirmExecution | Out-Null
Invoke-KilledChild $f 'Recover'
$s = Assert-Pending $f 'Recovering' 'Killed recovery'
$restored = @($s.CurrentRun.Operations | Where-Object { $_.RecoveryState -eq 'Done' })
Assert-True ($restored.Count -eq 1 -and $null -ne $restored[0].Before) 'Killed recovery durably records exactly one restored original file'
foreach ($op in $s.CurrentRun.Operations) {
    $side = 'After'; if ($op.RecoveryState -eq 'Done') { $side = 'Before' }
    Assert-OperationFile $f $op $side 'Killed recovery'
}
Assert-True ((Get-TestInventory $f.Production) -cne $f.Before -and -not $s.Services.worker) 'Killed recovery remains partially restored with worker stopped'
Assert-Blocked $f 'Killed recovery'
Invoke-RfRecovery -TargetConfigPath $f.Config -ConfirmExecution | Out-Null
Assert-Recovered $f 'Resumed killed recovery'

# Exception after one recovery operation must retain recovery eligibility, not mark complete.
$f = New-TestFixture 'recovery-injected-failure'
Invoke-RfDeployment -PlanPath $f.Plan -ConfirmExecution | Out-Null
Assert-Rejected { Invoke-RfRecovery -TargetConfigPath $f.Config -ConfirmExecution -FailAfterFiles 1 } 'Injected recovery failure is reported'
$s = Assert-Pending $f 'NeedsIntervention' 'Failed recovery'
$restored = @($s.CurrentRun.Operations | Where-Object { $_.RecoveryState -eq 'Done' })
Assert-True ($restored.Count -eq 1) 'Failed recovery durably records its first completed restoration'
Assert-OperationFile $f $restored[0] 'Before' 'Failed recovery'
Assert-True ((Get-TestInventory $f.Production) -cne $f.Before -and -not $s.Services.worker) 'Failed recovery leaves a partial restore with worker stopped'
Assert-Blocked $f 'Failed recovery'
Invoke-RfRecovery -TargetConfigPath $f.Config -ConfirmExecution | Out-Null
Assert-Recovered $f 'Retried failed recovery'

# Safe abort before application must not strand services or create a pending operation.
$f = New-TestFixture 'service-stop-failure'
Assert-Rejected { Invoke-RfDeployment -PlanPath $f.Plan -ConfirmExecution -FailServiceStop } 'Injected stop failure is reported'
$s = Get-RfStatus -TargetConfigPath $f.Config
Assert-True ((Get-TestInventory $f.Production) -ceq $f.Before) 'Stop failure makes no production file mutations'
Assert-True ((Get-FileHash -LiteralPath (Join-Path $f.State 'baseline.json')).Hash -eq $f.BaselineHash) 'Stop failure preserves adopted baseline'
Assert-True ($s.CurrentRun.Status -eq 'Aborted' -and @($s.PendingRuns).Count -eq 0) 'Stop failure is safely Aborted, not pending'
Assert-True (@($s.CurrentRun.Operations | Where-Object { $_.State -ne 'Pending' }).Count -eq 0 -and -not $s.CurrentRun.StartupAttempted) 'Stop failure never starts file application or application startup'
Assert-InitialServices $s 'Stop failure'
$retry = Join-Path $f.Home 'stop-retry.json'
New-RfPlan -PackagePath $f.Package -TargetConfigPath $f.Config -OutputPath $retry | Out-Null
Invoke-RfDeployment -PlanPath $retry -ConfirmExecution | Out-Null
$s = Get-RfStatus -TargetConfigPath $f.Config
Assert-True ($s.CurrentRun.Status -eq 'Succeeded' -and @($s.PendingRuns).Count -eq 0) 'Safe abort permits a successful fresh deployment retry'
Assert-True (([IO.File]::ReadAllText((Join-Path $f.Production 'bin/version.txt'))) -ceq '2.0.0') 'Fresh retry installs requested version'
Invoke-RfRecovery -TargetConfigPath $f.Config -ConfirmExecution | Out-Null
Assert-Recovered $f 'Stop failure fresh retry recovery'

# Once startup was attempted, no silent automatic rollback is allowed.
$f = New-TestFixture 'service-start-failure'
Assert-Rejected { Invoke-RfDeployment -PlanPath $f.Plan -ConfirmExecution -FailServiceStart } 'Injected start failure is reported'
$s = Assert-Pending $f 'NeedsIntervention' 'Start failure'
Assert-True ($s.CurrentRun.StartupAttempted -and @($s.CurrentRun.Operations | Where-Object { $_.State -ne 'Done' }).Count -eq 0) 'Start failure occurs after all files are durably applied and startup attempted'
foreach ($op in $s.CurrentRun.Operations) { Assert-OperationFile $f $op 'After' 'Start failure' }
Assert-True ((Get-TestInventory $f.Production) -cne $f.Before -and -not $s.Services.worker -and -not $s.Services.optional) 'Start failure retains deployed files and stops simulated services for intervention'
Assert-Blocked $f 'Start failure'
Invoke-RfRecovery -TargetConfigPath $f.Config -ConfirmExecution | Out-Null
Assert-Recovered $f 'Start failure explicit recovery'
Write-Host "All $script:passed assertions passed. Fixtures retained at $Root"
