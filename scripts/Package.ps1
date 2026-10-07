param(
    [Parameter(Mandatory=$true)][string]$BuildPath,
    [Parameter(Mandatory=$true)][string]$TargetId,
    [Parameter(Mandatory=$true)][string]$TargetFilesPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$BuildPath = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BuildPath))
$TargetFilesPath = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetFilesPath))
$OutputPath = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
if ($TargetId -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') { throw 'Invalid TargetId.' }
if (Test-Path $OutputPath) { throw 'Package output must be a fresh directory.' }
$build = Get-Content (Join-Path $BuildPath 'build.json') -Raw | ConvertFrom-Json
Import-Module (Join-Path $PSScriptRoot '../src/ReleaseFlow.psm1') -Force
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$package = Join-Path $OutputPath 'package'
$app = Join-Path $package 'app'
$tools = Join-Path $package 'tools'
New-Item -ItemType Directory -Path $app,$tools -Force | Out-Null
# Refuse links before copying build output or target overlays.
foreach ($root in @((Join-Path $BuildPath 'app'), $TargetFilesPath)) {
    if (-not (Test-Path $root -PathType Container)) { throw "Missing input directory: $root" }
    foreach ($item in @((Get-Item $root -Force)) + @(Get-ChildItem $root -Recurse -Force)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Links are unsupported: $($item.FullName)" }
    }
}
Copy-Item (Join-Path $BuildPath 'app/*') $app -Recurse -Force
# Only this target's non-secret application configuration is included.
Copy-Item (Join-Path $TargetFilesPath '*') $app -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot '../src/ReleaseFlow.psm1') $tools
Copy-Item (Join-Path $PSScriptRoot 'Deploy.ps1') $tools
Copy-Item (Join-Path $PSScriptRoot 'Recover.ps1') $tools
$metadata = @{SchemaVersion=1; TargetId=$TargetId; Version=$build.Version; Commit=$build.Commit; ToolVersion='0.1.0-demo'}
$metadata | ConvertTo-Json | Set-Content (Join-Path $package 'package.json') -Encoding UTF8
New-RfManifest -Root $app -OutputPath (Join-Path $package 'manifest.json') | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $OutputPath "$TargetId.zip"
[IO.Compression.ZipFile]::CreateFromDirectory($package, $zip)
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
[IO.File]::WriteAllText("$zip.sha256", $hash, (New-Object Text.UTF8Encoding($false)))
Write-Host "Packaged $TargetId from existing build: $zip"
