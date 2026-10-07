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
Import-Module (Join-Path $PSScriptRoot '../src/ReleaseFlow.psm1') -Force
# Validate every input and output ancestor before creating or copying any file.
Assert-RfSafePath -Path $OutputPath
foreach ($root in @((Join-Path $BuildPath 'app'), $TargetFilesPath)) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Missing input directory: $root" }
    Assert-RfSafePath -Path $root -Recurse
    if ($OutputPath -eq $root -or $OutputPath.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $root.StartsWith($OutputPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Package output and input roots must not overlap.' }
}
Assert-RfSafePath -Path (Join-Path $BuildPath 'build.json')
$build = Get-Content -LiteralPath (Join-Path $BuildPath 'build.json') -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$package = Join-Path $OutputPath 'package'
$app = Join-Path $package 'app'
$tools = Join-Path $package 'tools'
New-Item -ItemType Directory -Path $app,$tools -Force | Out-Null
Copy-Item (Join-Path $BuildPath 'app/*') $app -Recurse -Force
# Only this target's non-secret application configuration is included.
Copy-Item (Join-Path $TargetFilesPath '*') $app -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot '../src/ReleaseFlow.psm1') $tools
Copy-Item (Join-Path $PSScriptRoot 'Deploy.ps1') $tools
Copy-Item (Join-Path $PSScriptRoot 'Recover.ps1') $tools
$metadata = @{SchemaVersion=1; TargetId=$TargetId; Version=$build.Version; Commit=$build.Commit; ToolVersion=(Get-RfToolVersion)}
$metadata | ConvertTo-Json | Set-Content (Join-Path $package 'package.json') -Encoding UTF8
New-RfManifest -Root $app -OutputPath (Join-Path $package 'manifest.json') | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $OutputPath "$TargetId.zip"
[IO.Compression.ZipFile]::CreateFromDirectory($package, $zip)
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
[IO.File]::WriteAllText("$zip.sha256", $hash, (New-Object Text.UTF8Encoding($false)))
Write-Host "Packaged $TargetId from existing build: $zip"
