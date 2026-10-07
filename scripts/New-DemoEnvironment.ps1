param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Root))
if (Test-Path $Root) { throw 'Demo root must not exist. No existing directory will be reset.' }
New-Item -ItemType Directory -Path $Root | Out-Null
foreach ($version in @('1.0.0','2.0.0')) {
    & (Join-Path $PSScriptRoot 'Build.ps1') -Version $version -OutputPath (Join-Path $Root "build/$version")
}
foreach ($target in @('node-a','node-b')) {
    $overlay = Join-Path $Root "overlays/$target"
    New-Item -ItemType Directory -Path (Join-Path $overlay 'config') -Force | Out-Null
    @{ Node=$target; Endpoint="https://example.invalid/$target" } | ConvertTo-Json | Set-Content (Join-Path $overlay 'config/app.json') -Encoding UTF8
    $production = Join-Path $Root "targets/$target/production"
    New-Item -ItemType Directory -Path $production -Force | Out-Null
    Copy-Item (Join-Path $Root 'build/1.0.0/app/*') $production -Recurse
    Copy-Item (Join-Path $overlay '*') $production -Recurse
    New-Item -ItemType Directory -Path (Join-Path $production 'data') -Force | Out-Null
    'Do not modify runtime data' | Set-Content (Join-Path $production 'data/customer.txt') -Encoding UTF8
    '{"Preserve":"site-owned configuration"}' | Set-Content (Join-Path $production 'config/local.json') -Encoding UTF8
    $config = @{
        SchemaVersion=1; TargetId=$target; ProductionPath=$production
        StatePath=(Join-Path $Root "targets/$target/state")
        ManagedPaths=@('bin','config/app.json'); ProtectedPaths=@('data','config/local.json')
        ServiceMode='Simulated'; Services=@(@{Name='worker';InitiallyRunning=$true},@{Name='optional';InitiallyRunning=$false})
        StopOrder=@('worker','optional'); StartOrder=@('optional','worker')
        HealthCheck=@{Mode='Simulated';Fail=$false}
    }
    $config | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Root "$target.json") -Encoding UTF8
    foreach ($version in @('1.0.0','2.0.0')) {
        $out = Join-Path $Root "packages/$version/$target"
        & (Join-Path $PSScriptRoot 'Package.ps1') -BuildPath (Join-Path $Root "build/$version") -TargetId $target -TargetFilesPath $overlay -OutputPath $out
        $archive = Join-Path $out "$target.zip"
        & (Join-Path $PSScriptRoot 'Deliver.ps1') -ArchivePath $archive -ExpectedSha256 ((Get-Content "$archive.sha256" -Raw).Trim()) -DestinationPath (Join-Path $Root "inbox/$target/$version")
    }
}
Write-Host "Prepared isolated local fixtures: $Root"
