param(
    [Parameter(Mandatory=$true)][string]$ArchivePath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
    [Parameter(Mandatory=$true)][string]$DestinationPath
)
$ErrorActionPreference = 'Stop'
$ArchivePath = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ArchivePath))
$DestinationPath = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath))
if (Test-Path $DestinationPath) { throw 'Delivery requires a new destination; never merge into an existing directory.' }
$destination = [IO.Path]::GetFullPath($DestinationPath)
$prefix = $destination.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
# Avoid extraction through an existing junction in any ancestor.
$ancestor = [IO.DirectoryInfo]$destination
while ($null -ne $ancestor) {
    if ($ancestor.Exists -and (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'Delivery path contains a reparse point.' }
    $ancestor = $ancestor.Parent
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
# Hash and extract from the same read-locked stream; prevent replacement between checks.
$stream = [IO.File]::Open([IO.Path]::GetFullPath($ArchivePath), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
$archive = $null
try {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actual = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') } finally { $sha.Dispose() }
    if ($actual -ne $ExpectedSha256) { throw 'Archive checksum mismatch.' }
    $stream.Position = 0
    $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Read, $true)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    # Validate the entire archive before writing any member.
    foreach ($entry in $archive.Entries) {
        $name = $entry.FullName.Replace('\','/')
        $parts = $name.TrimEnd('/').Split('/')
        if ([string]::IsNullOrWhiteSpace($name) -or $name.StartsWith('/') -or $name.Contains(':') -or @($parts | Where-Object { $_ -in @('','..','.') -or $_.EndsWith('.') -or $_.EndsWith(' ') -or $_ -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)' }).Count -gt 0) { throw "Unsafe archive path: $name" }
        $fileType = ($entry.ExternalAttributes -shr 16) -band 61440
        if ($fileType -eq 40960 -or (($entry.ExternalAttributes -band 1024) -ne 0)) { throw 'Archive links are unsupported.' }
        $full = [IO.Path]::GetFullPath((Join-Path $destination $name))
        if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or -not $seen.Add($name.TrimEnd('/'))) { throw "Conflicting archive path: $name" }
    }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    foreach ($entry in $archive.Entries) {
        $full = Join-Path $destination $entry.FullName.Replace('\','/')
        if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
            New-Item -ItemType Directory -Path $full -Force | Out-Null
        } else {
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($full)) -Force | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $full, $false)
        }
    }
} finally {
    if ($null -ne $archive) { $archive.Dispose() }
    $stream.Dispose()
}
Write-Host "Delivered only; no production deployment executed: $destination"
