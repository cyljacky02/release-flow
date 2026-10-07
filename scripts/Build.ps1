param(
    [Parameter(Mandatory=$true)][string]$Version,
    [string]$OutputPath = (Join-Path $PSScriptRoot '../.work/build'),
    [string]$Commit = 'local-demo'
)
$ErrorActionPreference = 'Stop'
$OutputPath = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
# Sample application's authoritative build entry. Replace its body for a real project.
if (Test-Path $OutputPath) { throw "Build output already exists: $OutputPath. Use a fresh output directory." }
$app = Join-Path $OutputPath 'app'
New-Item -ItemType Directory -Path (Join-Path $app 'bin') -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot '../examples/application/Application.ps1') (Join-Path $app 'bin/Application.ps1')
[IO.File]::WriteAllText((Join-Path $app 'bin/version.txt'), $Version, (New-Object Text.UTF8Encoding($false)))
if ($Version -eq '1.0.0') {
    [IO.File]::WriteAllText((Join-Path $app 'bin/legacy.txt'), 'Removed in version 2', (New-Object Text.UTF8Encoding($false)))
} else {
    [IO.File]::WriteAllText((Join-Path $app 'bin/feature.txt'), 'Added in version 2', (New-Object Text.UTF8Encoding($false)))
}
@{ SchemaVersion=1; Version=$Version; Commit=$Commit } | ConvertTo-Json | Set-Content (Join-Path $OutputPath 'build.json') -Encoding UTF8
Write-Host "Built $Version once: $OutputPath"
