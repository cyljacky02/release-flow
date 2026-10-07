param([string]$Root = (Join-Path $PSScriptRoot ('../.work/safety-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root))
if (Test-Path $Root) { throw 'Fresh test root required.' }
New-Item -ItemType Directory -Path $Root | Out-Null
Import-Module (Join-Path $PSScriptRoot '../src/ReleaseFlow.psm1') -Force
$script:passed=0; $script:failures=@()
function Check([bool]$Condition,[string]$Name) {
    if ($Condition) { $script:passed++; Write-Host "PASS: $Name" }
    else { $script:failures += $Name; Write-Host "FAIL: $Name" }
}
function Throws([scriptblock]$Action) {
    try { & $Action | Out-Null; return $false } catch { Write-Host "Rejected: $($_.Exception.Message)"; return $true }
}
function New-Fixture([string]$Name) {
    $path=Join-Path $Root $Name
    $prod=Join-Path $path 'production'; $state=Join-Path $path 'state'
    New-Item -ItemType Directory -Path (Join-Path $prod 'bin'),(Join-Path $prod 'data') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $prod 'bin/version.txt'),'old')
    [IO.File]::WriteAllText((Join-Path $prod 'data/customer.txt'),'protected data')
    $version=Get-RfToolVersion
    foreach($v in @('old','new')) {
        $package=Join-Path $path $v
        New-Item -ItemType Directory -Path (Join-Path $package 'app/bin') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $package 'app/bin/version.txt'),$v)
        @{SchemaVersion=1;TargetId=$Name;Version=$v;Commit=$v;ToolVersion=$version} | ConvertTo-Json | Set-Content (Join-Path $package 'package.json') -Encoding UTF8
        New-RfManifest -Root (Join-Path $package 'app') -OutputPath (Join-Path $package 'manifest.json') | Out-Null
    }
    $config=@{SchemaVersion=1;TargetId=$Name;ProductionPath=$prod;StatePath=$state;ManagedPaths=@('bin');ProtectedPaths=@('data');ServiceMode='Simulated';Services=@(@{Name='worker';InitiallyRunning=$true});StopOrder=@('worker');StartOrder=@('worker');HealthCheck=@{Mode='Simulated';Fail=$false}}
    $configPath=Join-Path $path 'target.json'; $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
    return @{Root=$path;Production=$prod;State=$state;Config=$configPath;New=(Join-Path $path 'new');Old=(Join-Path $path 'old')}
}
# Exact symptom: in-place write to a managed hardlink also mutates protected data.
$f=New-Fixture 'hardlink'
$protected=Join-Path $f.Production 'data/customer.txt'
Remove-Item $protected
New-Item -ItemType HardLink -Path $protected -Target (Join-Path $f.Production 'bin/version.txt') | Out-Null
$before=(Get-FileHash $protected).Hash
$rejected=Throws {
    New-RfBaseline -TargetConfigPath $f.Config | Out-Null
    $plan=Join-Path $f.Root 'plan.json'
    New-RfPlan -PackagePath $f.New -TargetConfigPath $f.Config -OutputPath $plan | Out-Null
    Invoke-RfDeployment -PlanPath $plan -ConfirmExecution | Out-Null
}
Check $rejected 'Managed/protected hard-link alias rejected before deployment'
Check ((Get-FileHash $protected).Hash -eq $before) 'Protected hard-link content never changed'
# Exact symptom: Package creates files through a junction before reporting rejection.
$f=New-Fixture 'junction'
$build=Join-Path $f.Root 'build'; $overlay=Join-Path $f.Root 'overlay'
New-Item -ItemType Directory -Path $build,$overlay -Force | Out-Null
Copy-Item (Join-Path $f.New 'app') $build -Recurse
@{Version='new';Commit='new'} | ConvertTo-Json | Set-Content (Join-Path $build 'build.json') -Encoding UTF8
'nonsecret' | Set-Content (Join-Path $overlay 'metadata.txt') -Encoding UTF8
$outside=Join-Path $f.Root 'outside'; New-Item -ItemType Directory -Path $outside | Out-Null
$link=Join-Path $f.Root 'output-junction'; New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
$rejected=Throws { & (Join-Path $PSScriptRoot '../scripts/Package.ps1') -BuildPath $build -TargetId junction -TargetFilesPath $overlay -OutputPath (Join-Path $link 'package-output') }
Check $rejected 'Package junction ancestor rejected'
Check (@(Get-ChildItem $outside -Recurse -Force).Count -eq 0) 'Package rejection writes nothing through junction'
# Exact symptom: durable Preparing journal is ignored when current pointer replacement fails.
$f=New-Fixture 'pointer'
New-RfBaseline -TargetConfigPath $f.Config | Out-Null
$up=Join-Path $f.Root 'up.json'; New-RfPlan -PackagePath $f.New -TargetConfigPath $f.Config -OutputPath $up | Out-Null
Invoke-RfDeployment -PlanPath $up -ConfirmExecution | Out-Null
$down=Join-Path $f.Root 'down.json'; New-RfPlan -PackagePath $f.Old -TargetConfigPath $f.Config -OutputPath $down | Out-Null
$pointer=Join-Path $f.State 'current.json'
$stream=[IO.File]::Open($pointer,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try { Check (Throws { Invoke-RfDeployment -PlanPath $down -ConfirmExecution }) 'Pointer persistence fault reported' }
finally { $stream.Dispose() }
$pending=@(Get-ChildItem (Join-Path $f.State 'runs') -Directory | ForEach-Object { Get-Content (Join-Path $_.FullName 'journal.json') -Raw | ConvertFrom-Json } | Where-Object { $_.Status -eq 'Preparing' })
Check ($pending.Count -eq 1) 'Durable unfinished preparation remains available'
Check (Throws { New-RfPlan -PackagePath $f.Old -TargetConfigPath $f.Config -OutputPath (Join-Path $f.Root 'next.json') }) 'Orphan unfinished journal blocks new plan'
Check (Throws { Invoke-RfDeployment -PlanPath $down -ConfirmExecution }) 'Orphan unfinished journal blocks direct deployment'
Check (Throws { Resolve-RfPreparation -TargetConfigPath $f.Config -RunId $pending[0].RunId }) 'Abandoning preparation requires confirmation'
Resolve-RfPreparation -TargetConfigPath $f.Config -RunId $pending[0].RunId -ConfirmExecution | Out-Null
Check ((Get-Content (Join-Path $f.Production 'bin/version.txt') -Raw) -eq 'new') 'Resolving orphan preparation never changes application'
New-RfPlan -PackagePath $f.Old -TargetConfigPath $f.Config -OutputPath (Join-Path $f.Root 'resolved.json') | Out-Null
Check $true 'Explicit safe preparation resolution unblocks planning'
# A link introduced after review must still be rejected during execution revalidation.
$f=New-Fixture 'late-link'
New-RfBaseline -TargetConfigPath $f.Config | Out-Null
$plan=Join-Path $f.Root 'plan.json'
New-RfPlan -PackagePath $f.New -TargetConfigPath $f.Config -OutputPath $plan | Out-Null
$protected=Join-Path $f.Production 'data/customer.txt'
Remove-Item $protected
New-Item -ItemType HardLink -Path $protected -Target (Join-Path $f.Production 'bin/version.txt') | Out-Null
$before=(Get-FileHash $protected).Hash
Check (Throws { Invoke-RfDeployment -PlanPath $plan -ConfirmExecution }) 'Hard link introduced after approval blocks execution'
Check ((Get-FileHash $protected).Hash -eq $before) 'Late protected alias remains unchanged'
# A crash before the first journal write must not be silently ignored either.
$f=New-Fixture 'missing-journal'
New-RfBaseline -TargetConfigPath $f.Config | Out-Null
$unknown=Join-Path $f.State ('runs/' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $unknown -Force | Out-Null
Check (Throws { New-RfPlan -PackagePath $f.New -TargetConfigPath $f.Config -OutputPath (Join-Path $f.Root 'plan.json') }) 'Run directory without durable journal blocks planning'
Write-Host "$script:passed safety assertions passed; $($script:failures.Count) failed. Fixtures: $Root"
if ($script:failures.Count) { throw ($script:failures -join '; ') }
