# Release Flow reusable core. Windows PowerShell 5.1+; simulated services only.
# Hashes detect changes, not provenance. Journaling is not a power-loss guarantee.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:RfToolVersion = '0.1.2-demo'
$script:RfModulePath = $PSCommandPath

function Stop-Rf($Code, $Message) { throw "RF_${Code}: $Message" }
function ConvertTo-RfMap($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $Value.Keys) { $result[$key] = ConvertTo-RfMap $Value[$key] }
        return $result
    }
    if ($Value -is [pscustomobject]) {
        $result = @{}
        foreach ($p in $Value.PSObject.Properties) { $result[$p.Name] = ConvertTo-RfMap $p.Value }
        return $result
    }
    if ($Value -is [array]) {
        $result = @(); foreach ($item in $Value) { $result += ,(ConvertTo-RfMap $item) }
        return ,$result
    }
    return $Value
}
function Get-RfToolVersion { return $script:RfToolVersion }
function Assert-RfSingleLink($Path) {
    if (-not [IO.File]::Exists($Path)) { return }
    if ($env:OS -ne 'Windows_NT') { Stop-Rf 'UnsupportedPlatform' 'Hard-link validation currently requires Windows.' }
    if (-not ('ReleaseFlow.NativeFileIdentity' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace ReleaseFlow {
    public static class NativeFileIdentity {
        [StructLayout(LayoutKind.Sequential)]
        private struct Info {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME Creation;
            public System.Runtime.InteropServices.ComTypes.FILETIME Access;
            public System.Runtime.InteropServices.ComTypes.FILETIME Write;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", SetLastError=true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out Info info);
        public static uint LinkCount(SafeFileHandle handle) {
            Info info;
            if (!GetFileInformationByHandle(handle, out info)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return info.Links;
        }
    }
}
'@
    }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try { if ([ReleaseFlow.NativeFileIdentity]::LinkCount($stream.SafeFileHandle) -ne 1) { Stop-Rf 'HardLink' "Multiple file names refer to $Path; hard links are unsupported." } }
    finally { $stream.Dispose() }
}
function Assert-RfSafePath {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Path, [switch]$Recurse)
    $full = Get-RfFullPath $Path
    Assert-RfNoReparse $full
    if ([IO.File]::Exists($full)) { Assert-RfSingleLink $full }
    elseif ($Recurse -and [IO.Directory]::Exists($full)) { [void](Get-RfInventory $full '' $true) }
}
function Assert-RfRelativePath {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
    [void](Get-RfRelative $Path)
}
function Read-RfJson($Path) {
    Assert-RfNoReparse $Path
    Assert-RfSingleLink $Path
    if (-not [IO.File]::Exists($Path)) { Stop-Rf 'MissingFile' $Path }
    try { return ConvertTo-RfMap (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path))) }
    catch { Stop-Rf 'InvalidJson' "$Path : $_" }
}
function Get-RfJson($Value) { return ConvertTo-Json -InputObject $Value -Depth 60 -Compress }
function Write-RfJson($Path, $Value) {
    Assert-RfNoReparse $Path
    Assert-RfSingleLink $Path
    $parent = [IO.Path]::GetDirectoryName($Path)
    [void][IO.Directory]::CreateDirectory($parent)
    $temp = Join-Path $parent ([IO.Path]::GetRandomFileName())
    try {
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes((Get-RfJson $Value))
        $stream = [IO.File]::Open($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        if ([IO.File]::Exists($Path)) {
            # Windows PowerShell coerces a null string argument to an empty path.
            $backup = $temp + '.previous'
            try { [IO.File]::Replace($temp, $Path, $backup) }
            finally { if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) } }
        }
        else { [IO.File]::Move($temp, $Path) }
    } catch { Stop-Rf 'PersistenceFailed' "Cannot durably write $Path : $_" }
    finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}
function Get-RfHash($Path) {
    Assert-RfNoReparse $Path
    Assert-RfSingleLink $Path
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-RfTextHash($Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-RfFullPath($Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { Stop-Rf 'InvalidPath' 'An empty path is not allowed.' }
    $full = [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))
    if ($full -eq [IO.Path]::GetPathRoot($full)) { Stop-Rf 'UnsafeRoot' 'A filesystem root cannot be an involved root or file path.' }
    return $full.TrimEnd([char[]]@('\','/'))
}
function Test-RfUnder($Path, $Root) {
    return $Path.Equals($Root, [StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($Root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}
function Assert-RfNoReparse($Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Stop-Rf 'ReparsePoint' $cursor }
        }
        $next = [IO.Path]::GetDirectoryName($cursor)
        if ($next -eq $cursor) { break }; $cursor = $next
    }
}
function Get-RfRelative($Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { Stop-Rf 'UnsafeRelativePath' 'Empty path.' }
    $p = $Path.Replace('\', '/')
    if ([IO.Path]::IsPathRooted($p) -or $p.StartsWith('/') -or $p.Contains(':')) { Stop-Rf 'UnsafeRelativePath' $Path }
    foreach ($part in $p.Split('/')) {
        if (-not $part -or $part -eq '.' -or $part -eq '..' -or $part.EndsWith('.') -or $part.EndsWith(' ') -or $part -match '[\x00-\x1f<>"|?*]' -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            Stop-Rf 'UnsafeRelativePath' $Path
        }
    }
    return $p
}
function Join-RfPath($Root, $Relative) {
    $p = Get-RfRelative $Relative
    $full = Get-RfFullPath (Join-Path $Root $p.Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-RfUnder $full $Root) -or $full -eq $Root) { Stop-Rf 'UnsafeRelativePath' $Relative }
    Assert-RfNoReparse $full
    return $full
}
function Test-RfScope($Path, $Scopes) {
    foreach ($scope in $Scopes) {
        if ($Path.Equals($scope, [StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($scope + '/', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
function Get-RfInventory($Root, $ExcludePath = '', $ValidateOnly = $false, $AllowLockedPath = '') {
    Assert-RfNoReparse $Root
    if (-not [IO.Directory]::Exists($Root)) { Stop-Rf 'MissingDirectory' $Root }
    $files = @(); $seen = @{}
    # Enumerate one directory at a time; never recurse through a junction first.
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue($Root)
    while ($queue.Count -gt 0) {
        $dir = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $dir -Force)) {
            Assert-RfNoReparse $item.FullName
            $relative = Get-RfRelative ($item.FullName.Substring($Root.Length + 1))
            if ($seen.ContainsKey($relative)) { Stop-Rf 'CaseCollision' $relative }; $seen[$relative] = $true
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) }
            else {
                if ($item.FullName -ne $AllowLockedPath) { Assert-RfSingleLink $item.FullName }
                if ($item.FullName -ne $ExcludePath -and -not $ValidateOnly) {
                    $files += [ordered]@{ Path = $relative; Sha256 = Get-RfHash $item.FullName; Length = [long]$item.Length }
                }
            }
        }
    }
    return @($files | Sort-Object { $_.Path })
}
function Get-RfManaged($Config) {
    return @(Get-RfInventory $Config.ProductionPath | Where-Object {
        (Test-RfScope $_.Path $Config.ManagedPaths) -and -not (Test-RfScope $_.Path $Config.ProtectedPaths)
    })
}
function Get-RfIndex($Files) {
    $index = @{}
    foreach ($file in @($Files)) {
        if ($null -eq $file -or -not $file.Contains('Path') -or -not $file.Contains('Sha256') -or -not $file.Contains('Length')) { Stop-Rf 'InvalidInventory' 'Expected Path, Sha256, Length.' }
        $path = Get-RfRelative ([string]$file.Path)
        if ($path -cne $file.Path -or $file.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or [long]$file.Length -lt 0) { Stop-Rf 'InvalidInventory' $path }
        if ($index.ContainsKey($path)) { Stop-Rf 'CaseCollision' $path }
        $index[$path] = $file
    }
    return $index
}
function Test-RfSame($A, $B) {
    if ($null -eq $A -or $null -eq $B) { return ($null -eq $A -and $null -eq $B) }
    return ($A.Sha256 -eq $B.Sha256 -and [long]$A.Length -eq [long]$B.Length)
}
function Assert-RfInventoryEqual($Expected, $Actual, $Code) {
    $a = Get-RfIndex $Expected; $b = Get-RfIndex $Actual
    if ($a.Count -ne $b.Count) { Stop-Rf $Code 'File inventory differs.' }
    foreach ($p in $a.Keys) { if (-not $b.ContainsKey($p) -or -not (Test-RfSame $a[$p] $b[$p])) { Stop-Rf $Code $p } }
}
function Read-RfConfig($Path) {
    $full = Get-RfFullPath $Path; $c = Read-RfJson $full
    foreach ($key in @('SchemaVersion','TargetId','ProductionPath','StatePath','ManagedPaths','ProtectedPaths','ServiceMode','Services','StopOrder','StartOrder','HealthCheck')) {
        if (-not $c.ContainsKey($key)) { Stop-Rf 'InvalidConfig' "Missing $key" }
    }
    if ($c.SchemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace($c.TargetId)) { Stop-Rf 'InvalidConfig' 'SchemaVersion or TargetId.' }
    if ($c.ServiceMode -cne 'Simulated' -or $c.HealthCheck.Mode -cne 'Simulated') { Stop-Rf 'UnsupportedMode' 'Only simulated services and health checks are implemented; real mode is refused.' }
    if (-not $c.HealthCheck.ContainsKey('Fail') -or $c.HealthCheck.Fail -isnot [bool]) { Stop-Rf 'InvalidConfig' 'HealthCheck.Fail must be boolean.' }
    foreach ($key in @('ProductionPath','StatePath')) {
        if (-not [IO.Path]::IsPathRooted($c[$key])) { Stop-Rf 'InvalidConfig' "$key must be absolute." }
        $c[$key] = Get-RfFullPath $c[$key]; Assert-RfNoReparse $c[$key]
    }
    if ((Test-RfUnder $c.ProductionPath $c.StatePath) -or (Test-RfUnder $c.StatePath $c.ProductionPath)) { Stop-Rf 'OverlappingRoots' 'State and production overlap.' }
    if (Test-RfUnder $full $c.ProductionPath) { Stop-Rf 'OverlappingRoots' 'Target definition must be outside production.' }
    if (Test-RfUnder $PSCommandPath $c.ProductionPath) { Stop-Rf 'OverlappingRoots' 'Core must be outside production.' }
    if (-not [IO.Directory]::Exists($c.ProductionPath)) { Stop-Rf 'MissingDirectory' $c.ProductionPath }
    foreach ($key in @('ManagedPaths','ProtectedPaths')) {
        if ($c[$key] -isnot [array]) { Stop-Rf 'InvalidConfig' "$key must be an array." }
        $seen = @{}
        foreach ($p in $c[$key]) {
            $r = Get-RfRelative $p
            if ($r -cne $p -or $seen.ContainsKey($r)) { Stop-Rf 'InvalidConfig' "Noncanonical/duplicate $key : $p" }
            $seen[$r] = $true; [void](Join-RfPath $c.ProductionPath $r)
        }
    }
    if ($c.ManagedPaths.Count -eq 0) { Stop-Rf 'InvalidConfig' 'ManagedPaths cannot be empty.' }
    $names = @{}
    foreach ($s in @($c.Services)) {
        if (-not $s.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace($s.Name) -or -not $s.ContainsKey('InitiallyRunning') -or $s.InitiallyRunning -isnot [bool] -or $names.ContainsKey($s.Name)) { Stop-Rf 'InvalidConfig' 'Invalid service declaration.' }
        $names[$s.Name] = $true
    }
    foreach ($key in @('StopOrder','StartOrder')) {
        if ($c[$key] -isnot [array] -or $c[$key].Count -ne $names.Count) { Stop-Rf 'InvalidConfig' "$key must list every service exactly once." }
        $seen = @{}
        foreach ($n in $c[$key]) { if (-not $names.ContainsKey($n) -or $seen.ContainsKey($n)) { Stop-Rf 'InvalidConfig' $key }; $seen[$n] = $true }
    }
    # Scan to reject junctions and case collisions, including retained content (conservative).
    [void](Get-RfInventory $c.ProductionPath '' $true)
    if ([IO.Directory]::Exists($c.StatePath)) { [void](Get-RfInventory $c.StatePath '' $true (Join-Path $c.StatePath 'target.lock')) }
    $c['_ConfigPath'] = $full
    return $c
}
function Enter-RfLock($Config) {
    Assert-RfNoReparse $Config.StatePath
    [void][IO.Directory]::CreateDirectory($Config.StatePath)
    $path = Join-Path $Config.StatePath 'target.lock'; Assert-RfNoReparse $path
    try {
        Assert-RfSingleLink $path
        return [IO.File]::Open($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    catch { Stop-Rf 'TargetLocked' 'Another executor holds the target lock (or the state directory is inaccessible).' }
}
function Get-RfCurrent($Config) {
    $path = Join-Path $Config.StatePath 'current.json'
    if (-not [IO.File]::Exists($path)) { return $null }
    $pointer = Read-RfJson $path
    $id = [guid]::Empty
    if (-not [guid]::TryParse([string]$pointer.RunId, [ref]$id)) { Stop-Rf 'InvalidJournal' 'Invalid run pointer.' }
    return Read-RfJson (Join-Path $Config.StatePath "runs/$id/journal.json")
}
function Get-RfRuns($Config) {
    $root = Join-Path $Config.StatePath 'runs'
    if (-not [IO.Directory]::Exists($root)) { return @() }
    $runs = @()
    foreach ($directory in @(Get-ChildItem -LiteralPath $root -Directory -Force)) {
        $id = [guid]::Empty
        if (-not [guid]::TryParse($directory.Name, [ref]$id)) { Stop-Rf 'InvalidJournal' 'Unexpected run directory.' }
        $journal = Join-Path $directory.FullName 'journal.json'
        if (-not [IO.File]::Exists($journal)) { Stop-Rf 'IncompleteRun' "Run $id has no durable journal; manual inspection required." }
        $run = Read-RfJson $journal
        if ($run.SchemaVersion -ne 1 -or $run.RunId -ne $id.ToString() -or $run.TargetId -cne $Config.TargetId -or $run.ProductionPath -ne $Config.ProductionPath) { Stop-Rf 'InvalidJournal' "Run identity mismatch at $id" }
        $runs += $run
    }
    return @($runs)
}
function Get-RfPendingRuns($Config) {
    return @(Get-RfRuns $Config | Where-Object { $_.Status -notin @('Succeeded','Recovered','AutoRecovered','Aborted') })
}
function Assert-RfComplete($Config) {
    $pending = @(Get-RfPendingRuns $Config)
    if ($pending.Count -gt 0) { Stop-Rf 'IncompleteRun' "Run $($pending[0].RunId) is $($pending[0].Status); recovery/intervention required, including orphan journals." }
    # Validate the pointer too; it is an index, not the authority for completeness.
    [void](Get-RfCurrent $Config)
}
function Get-RfRecoveryCandidate($Config) {
    $run = Get-RfCurrent $Config
    $seen = @{}
    while ($null -ne $run -and $run.Status -eq 'Aborted') {
        if ($seen.ContainsKey($run.RunId)) { Stop-Rf 'InvalidJournal' 'Recovery lineage contains a cycle.' }
        $seen[$run.RunId] = $true
        # Skip only proven untouched attempts, never actual recovered deployments.
        if ($run.ToolVersion -ne $script:RfToolVersion -or $run.StartupAttempted -or $null -ne $run.BaselineAfter -or @($run.Operations | Where-Object { $_.State -ne 'Pending' -or $_.RecoveryState -ne 'Pending' }).Count -gt 0 -or -not $run.Contains('PreviousRunId')) { Stop-Rf 'RecoveryNotEligible' 'Aborted attempt has no compatible untouched lineage.' }
        if ($run.TargetConfigSha256 -ne (Get-RfHash $Config._ConfigPath)) { Stop-Rf 'ConfigChanged' 'Aborted attempt definition changed.' }
        Assert-RfInventoryEqual $run.BeforeManagedFiles (Get-RfManaged $Config) 'RecoveryDrift'
        if ((Get-RfCanonical (Read-RfBaseline $Config)) -cne (Get-RfCanonical $run.BaselineBefore) -or (Get-RfCanonical (Get-RfServices $Config)) -cne (Get-RfCanonical $run.InitialServices)) { Stop-Rf 'RecoveryDrift' 'Aborted attempt no longer matches its untouched baseline/services.' }
        if ($null -eq $run.PreviousRunId) { return $null }
        $previous = [guid]::Empty
        if (-not [guid]::TryParse([string]$run.PreviousRunId, [ref]$previous)) { Stop-Rf 'InvalidJournal' 'Invalid previous run identity.' }
        $matches = @(Get-RfRuns $Config | Where-Object { $_.RunId -eq $previous.ToString() })
        if ($matches.Count -ne 1) { Stop-Rf 'InvalidJournal' 'Previous run is missing.' }
        $run = $matches[0]
    }
    return $run
}
function Resolve-RfPreparation {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TargetConfigPath, [Parameter(Mandatory)][guid]$RunId, [switch]$ConfirmExecution)
    if (-not $ConfirmExecution) { Stop-Rf 'ConfirmationRequired' 'Explicit confirmation required to abandon an untouched preparation.' }
    $c = Read-RfConfig $TargetConfigPath; $lock = Enter-RfLock $c
    try {
        $matches = @(Get-RfRuns $c | Where-Object { $_.RunId -eq $RunId.ToString() })
        if ($matches.Count -ne 1) { Stop-Rf 'InvalidJournal' 'Preparation run not found.' }
        $run = $matches[0]
        if ($run.ToolVersion -ne $script:RfToolVersion -or $run.Status -ne 'Preparing' -or $run.BackupsComplete -or $run.StartupAttempted -or $run.ServiceEvents.Count -ne 0 -or $null -ne $run.ServiceIntent -or @($run.Operations | Where-Object { $_.State -ne 'Pending' }).Count -ne 0) { Stop-Rf 'UnsafePreparation' 'Only an untouched compatible Preparing run can be abandoned.' }
        if ($run.TargetConfigSha256 -ne (Get-RfHash $c._ConfigPath)) { Stop-Rf 'ConfigChanged' 'Preparation definition changed.' }
        Assert-RfInventoryEqual $run.BeforeManagedFiles (Get-RfManaged $c) 'Drift'
        if ((Get-RfCanonical (Read-RfBaseline $c)) -cne (Get-RfCanonical $run.BaselineBefore) -or (Get-RfCanonical (Get-RfServices $c)) -cne (Get-RfCanonical $run.InitialServices)) { Stop-Rf 'UnsafePreparation' 'Baseline or services changed since preparation.' }
        Set-RfPhase $c $run 'Aborted'
        Write-RfReport $c $run
        return [pscustomobject]$run
    } finally { $lock.Dispose() }
}
function Read-RfBaseline($Config) {
    $path = Join-Path $Config.StatePath 'baseline.json'
    if (-not [IO.File]::Exists($path)) { Stop-Rf 'BaselineRequired' 'Run New-RfBaseline explicitly after operator review.' }
    $b = Read-RfJson $path
    if ($b.SchemaVersion -ne 1 -or $b.TargetId -cne $Config.TargetId -or $b.ProductionPath -ne $Config.ProductionPath) { Stop-Rf 'InvalidBaseline' 'Baseline identity does not match target.' }
    [void](Get-RfIndex $b.Files)
    foreach ($f in $b.Files) {
        if (-not (Test-RfScope $f.Path $Config.ManagedPaths) -or (Test-RfScope $f.Path $Config.ProtectedPaths)) { Stop-Rf 'InvalidBaseline' $f.Path }
    }
    return $b
}
function Assert-RfDrift($Baseline, $Actual) {
    $a = Get-RfIndex $Actual
    foreach ($f in $Baseline.Files) {
        if (-not $a.ContainsKey($f.Path) -or -not (Test-RfSame $f $a[$f.Path])) { Stop-Rf 'Drift' $f.Path }
    }
}
function New-RfManifest {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$OutputPath)
    $rootFull = Get-RfFullPath $Root; $out = Get-RfFullPath $OutputPath
    Assert-RfNoReparse $out
    $manifest = [ordered]@{ SchemaVersion = 1; Files = @(Get-RfInventory $rootFull $out) }
    Write-RfJson $out $manifest
    return [pscustomobject]$manifest
}
function New-RfBaseline {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TargetConfigPath)
    $c = Read-RfConfig $TargetConfigPath; $lock = Enter-RfLock $c
    try {
        Assert-RfComplete $c
        $path = Join-Path $c.StatePath 'baseline.json'
        if ([IO.File]::Exists($path)) { Stop-Rf 'BaselineExists' 'Baseline replacement is not supported.' }
        $existingState = @(Get-ChildItem -LiteralPath $c.StatePath -Force | Where-Object { $_.Name -ne 'target.lock' })
        if ($existingState.Count -gt 0) { Stop-Rf 'StateExists' 'Existing state cannot be re-adopted; retain and investigate the previous state.' }
        $b = [ordered]@{ SchemaVersion = 1; TargetId = $c.TargetId; ProductionPath = $c.ProductionPath; Version = 'Adopted'; Commit = $null; LatestRunId = $null; Files = @(Get-RfManaged $c) }
        Write-RfJson $path $b
        return [pscustomobject]$b
    } finally { $lock.Dispose() }
}
function Get-RfPlanData($PackagePath, $Config) {
    $packageRoot = Get-RfFullPath $PackagePath
    foreach ($root in @($Config.StatePath, $Config.ProductionPath)) {
        if ((Test-RfUnder $packageRoot $root) -or (Test-RfUnder $root $packageRoot)) { Stop-Rf 'OverlappingRoots' 'Package, production and state roots must be disjoint.' }
    }
    $summaryFiles = @(Get-RfInventory $packageRoot)
    $pkgRaw = Read-RfJson (Join-Path $packageRoot 'package.json')
    $pkg = [ordered]@{}
    foreach ($key in @('SchemaVersion','TargetId','Version','Commit','ToolVersion')) {
        if (-not $pkgRaw.ContainsKey($key)) { Stop-Rf 'InvalidPackage' "Missing $key" }
        $pkg[$key] = $pkgRaw[$key]
    }
    if ($pkg.SchemaVersion -ne 1 -or $pkg.TargetId -cne $Config.TargetId -or [string]::IsNullOrWhiteSpace($pkg.Version)) { Stop-Rf 'TargetMismatch' 'Package schema, target or version is invalid.' }
    if ($pkg.ToolVersion -ne $script:RfToolVersion) { Stop-Rf 'ToolVersionMismatch' "Expected $script:RfToolVersion" }
    $manifest = Read-RfJson (Join-Path $packageRoot 'manifest.json')
    if ($manifest.SchemaVersion -ne 1) { Stop-Rf 'InvalidManifest' 'Unsupported schema.' }
    $desired = @($manifest.Files); $new = Get-RfIndex $desired
    Assert-RfInventoryEqual $desired (Get-RfInventory (Join-Path $packageRoot 'app')) 'ManifestMismatch'
    foreach ($f in $desired) {
        if (-not (Test-RfScope $f.Path $Config.ManagedPaths)) { Stop-Rf 'OutsideManagedPaths' $f.Path }
        if (Test-RfScope $f.Path $Config.ProtectedPaths) { Stop-Rf 'ProtectedPath' $f.Path }
        foreach ($protected in $Config.ProtectedPaths) {
            if (Test-RfScope $protected @($f.Path)) { Stop-Rf 'ProtectedPath' "File would obstruct protected scope: $($f.Path)" }
        }
    }
    $baseline = Read-RfBaseline $Config
    $actual = @(Get-RfManaged $Config); Assert-RfDrift $baseline $actual
    $old = Get-RfIndex $baseline.Files; $actualIndex = Get-RfIndex $actual
    $changes = @()
    foreach ($f in $desired) {
        $target = Join-RfPath $Config.ProductionPath $f.Path
        if (-not $old.ContainsKey($f.Path)) {
            if ($actualIndex.ContainsKey($f.Path) -or (Test-Path -LiteralPath $target)) { Stop-Rf 'UntrackedCollision' $f.Path }
            $kind = 'Added'; $before = $null
        } else {
            $before = $old[$f.Path]
            if (Test-RfSame $before $f) { continue }; $kind = 'Changed'
        }
        # Reject file/ancestor collisions, even if a removal could make room.
        $cursor = [IO.Path]::GetDirectoryName($target)
        while ($cursor -ne $Config.ProductionPath) {
            if ([IO.File]::Exists($cursor)) { Stop-Rf 'PathCollision' $f.Path }
            $cursor = [IO.Path]::GetDirectoryName($cursor)
        }
        $changes += [ordered]@{ Path = $f.Path; Kind = $kind; SourcePath = Join-RfPath (Join-Path $packageRoot 'app') $f.Path; TargetPath = $target; Before = $before; After = $f }
    }
    foreach ($f in $baseline.Files) {
        if (-not $new.ContainsKey($f.Path)) { $changes += [ordered]@{ Path = $f.Path; Kind = 'Removed'; SourcePath = $null; TargetPath = Join-RfPath $Config.ProductionPath $f.Path; Before = $f; After = $null } }
    }
    return [ordered]@{
        SchemaVersion = 1; ToolVersion = $script:RfToolVersion; TargetId = $Config.TargetId
        PackagePath = $packageRoot; TargetConfigPath = $Config._ConfigPath
        ProductionPath = $Config.ProductionPath; StatePath = $Config.StatePath
        SourceVersion = $baseline.Version; TargetVersion = $pkg.Version; Package = $pkg
        PackageSha256 = Get-RfTextHash (Get-RfJson $summaryFiles)
        TargetConfigSha256 = Get-RfHash $Config._ConfigPath
        BaselineSha256 = Get-RfHash (Join-Path $Config.StatePath 'baseline.json')
        ActualManagedFiles = $actual; DesiredFiles = $desired
        Changes = @($changes | Sort-Object { $_.Path })
        NoOp = ($changes.Count -eq 0 -and $baseline.Version -ceq $pkg.Version -and $baseline.Commit -ceq $pkg.Commit)
    }
}
function Get-RfCanonical($Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [System.Collections.IDictionary]) {
        $parts = @(); foreach ($k in @($Value.Keys | Sort-Object)) { $parts += (Get-RfJson ([string]$k)) + ':' + (Get-RfCanonical $Value[$k]) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [array]) { $parts = @(); foreach ($v in $Value) { $parts += Get-RfCanonical $v }; return '[' + ($parts -join ',') + ']' }
    return Get-RfJson $Value
}
function New-RfPlan {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$PackagePath, [Parameter(Mandatory)][string]$TargetConfigPath, [Parameter(Mandatory)][string]$OutputPath)
    $c = Read-RfConfig $TargetConfigPath
    # A preview before bootstrap must not initialize target state.
    [void](Read-RfBaseline $c)
    $lock = Enter-RfLock $c
    try {
        Assert-RfComplete $c
        $out = Get-RfFullPath $OutputPath
        if ((Test-RfUnder $out (Get-RfFullPath $PackagePath)) -or (Test-RfUnder $out $c.ProductionPath) -or $out -eq $c._ConfigPath -or $out -eq (Join-Path $c.StatePath 'baseline.json') -or $out -eq (Join-Path $c.StatePath 'current.json') -or (Test-RfUnder $out (Join-Path $c.StatePath 'runs'))) { Stop-Rf 'UnsafePlanOutput' $out }
        foreach ($reserved in @('target.lock','services.json')) {
            if ($out -eq (Join-Path $c.StatePath $reserved)) { Stop-Rf 'UnsafePlanOutput' $out }
        }
        $plan = Get-RfPlanData $PackagePath $c
        $plan['PlanSha256'] = Get-RfTextHash (Get-RfCanonical $plan)
        if (Test-Path -LiteralPath $out) { Stop-Rf 'PlanExists' 'Use a fresh plan output path.' }
        Write-RfJson $out $plan
        return [pscustomobject]$plan
    } finally { $lock.Dispose() }
}
function Save-RfRun($Config, $Run) {
    Write-RfJson (Join-Path $Config.StatePath "runs/$($Run.RunId)/journal.json") $Run
}
function Write-RfReport($Config, $Run) {
    # Derived reports never turn a verified deployment into an automatic rollback.
    $root = Join-Path $Config.StatePath "runs/$($Run.RunId)"
    try {
        $report = [ordered]@{
            SchemaVersion = 1; RunId = $Run.RunId; TargetId = $Run.TargetId
            Operator = $Run.Operator; SourceVersion = $Run.SourceVersion; TargetVersion = $Run.TargetVersion
            Status = $Run.Status; Mode = 'Simulated'; CreatedUtc = $Run.CreatedUtc; UpdatedUtc = $Run.UpdatedUtc
            PlanSha256 = $Run.PlanSha256; BackupsComplete = $Run.BackupsComplete
            ServiceEvents = $Run.ServiceEvents; Error = $Run.Error
            Changes = @($Run.Operations | ForEach-Object { [ordered]@{ Path=$_.Path; Kind=$_.Kind; State=$_.State; RecoveryState=$_.RecoveryState } })
        }
        Write-RfJson (Join-Path $root 'report.json') $report
        $text = @("Release Flow (simulated services)", "Run: $($Run.RunId)", "Target: $($Run.TargetId)", "Operator: $($Run.Operator)", "Versions: $($Run.SourceVersion) -> $($Run.TargetVersion)", "Status: $($Run.Status)", "Error: $($Run.Error)")
        foreach ($op in $Run.Operations) { $text += "$($op.Kind): $($op.Path) [$($op.State), recovery $($op.RecoveryState)]" }
        [IO.File]::WriteAllLines((Join-Path $root 'report.txt'), [string[]]$text, (New-Object Text.UTF8Encoding($false)))
        Write-RfJson (Join-Path $root 'report-status.json') @{ Status='Complete' }
    } catch {
        Write-Warning "Operation status remains $($Run.Status); report generation needs retry: $_"
        try { Write-RfJson (Join-Path $root 'report-status.json') @{ Status='Pending'; Error=[string]$_ } } catch { }
    }
}
function Save-RfRecoveryTools($Config, $RunRoot) {
    $tools = Join-Path $RunRoot 'tools'
    [void][IO.Directory]::CreateDirectory($tools)
    Copy-RfFile $script:RfModulePath (Join-Path $tools 'ReleaseFlow.psm1')
    Copy-RfFile $Config._ConfigPath (Join-Path $tools 'target-config.json')
    $entry = @'
param([switch]$ConfirmExecution)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ReleaseFlow.psm1') -Force
Invoke-RfRecovery -TargetConfigPath (Join-Path $PSScriptRoot 'target-config.json') -ConfirmExecution:$ConfirmExecution
'@
    [IO.File]::WriteAllText((Join-Path $tools 'Recover.ps1'), $entry, (New-Object Text.UTF8Encoding($false)))
}
function Save-RfArchive($Config, $Run) {
    $root = Join-Path $Config.StatePath "runs/$($Run.RunId)"
    $snapshot = Join-Path $root 'snapshot'
    $zip = Join-Path $root 'snapshot.zip'
    if (-not [IO.Directory]::Exists($snapshot) -or [IO.File]::Exists($zip)) { return }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($snapshot, $zip)
    } catch { Write-Warning "Snapshot remains available; ZIP archive needs retry: $_" }
}
function Set-RfPhase($Config, $Run, $Phase) {
    $Run.Status = $Phase; $Run.UpdatedUtc = [DateTime]::UtcNow.ToString('o'); Save-RfRun $Config $Run
}
function Get-RfServices($Config) {
    $path = Join-Path $Config.StatePath 'services.json'
    $services = @{}
    foreach ($s in @($Config.Services)) { $services[$s.Name] = $s.InitiallyRunning }
    if ([IO.File]::Exists($path)) {
        $stored = Read-RfJson $path
        if ($stored.Count -ne $services.Count) { Stop-Rf 'ServiceStateMismatch' 'Simulated service definitions changed.' }
        foreach ($n in $services.Keys) { if (-not $stored.ContainsKey($n) -or $stored[$n] -isnot [bool]) { Stop-Rf 'ServiceStateMismatch' $n } }
        return $stored
    }
    return $services
}
function Set-RfServices($Config, $Run, $Start, $FailBeforeTransition = $false) {
    $order = $Config.StopOrder; if ($Start) { $order = $Config.StartOrder }
    foreach ($n in $order) {
        $running = $false; if ($Start) { $running = $Run.InitialServices[$n] }
        if ($FailBeforeTransition -and $Run.Services[$n] -ne $running) { Stop-Rf 'InjectedServiceFailure' "Simulated transition failed for $n (Running=$running)." }
        $Run.ServiceIntent = [ordered]@{ Name = $n; Running = $running }; Save-RfRun $Config $Run
        $Run.Services[$n] = $running
        Write-RfJson (Join-Path $Config.StatePath 'services.json') $Run.Services
        $Run.ServiceEvents += [ordered]@{ Name = $n; Running = $running; Utc = [DateTime]::UtcNow.ToString('o') }
        $Run.ServiceIntent = $null; Save-RfRun $Config $Run
    }
}
function Get-RfAclMetadata($Path) {
    if ($env:OS -eq 'Windows_NT') { return (Get-Acl -LiteralPath $Path).Sddl }
    return $null
}
function Set-RfAclMetadata($Path, $Sddl) {
    if ($null -ne $Sddl) {
        if ($env:OS -ne 'Windows_NT') { Stop-Rf 'UnsupportedAcl' 'Windows ACL metadata cannot be restored on this platform.' }
        $acl = Get-Acl -LiteralPath $Path
        $acl.SetSecurityDescriptorSddlForm($Sddl)
        Set-Acl -LiteralPath $Path -AclObject $acl
    }
}
function Copy-RfFile($Source, $Target, $Metadata = $null) {
    Assert-RfNoReparse $Source; Assert-RfNoReparse $Target
    Assert-RfSingleLink $Source; Assert-RfSingleLink $Target
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target))
    # Overwrite in place to retain existing ACL; recovery restores captured metadata too.
    [IO.File]::Copy($Source, $Target, $true)
    if ($null -ne $Metadata) {
        Set-RfAclMetadata $Target $Metadata.Sddl
        [IO.File]::SetLastWriteTimeUtc($Target, [DateTime]::Parse($Metadata.LastWriteUtc).ToUniversalTime())
        [IO.File]::SetAttributes($Target, [IO.FileAttributes][int]$Metadata.Attributes)
    }
}
function Get-RfFileState($Path) {
    Assert-RfNoReparse $Path
    if ([IO.Directory]::Exists($Path)) { Stop-Rf 'PathCollision' $Path }
    if (-not [IO.File]::Exists($Path)) { return $null }
    return @{ Sha256 = Get-RfHash $Path; Length = (Get-Item -LiteralPath $Path -Force).Length }
}
function Assert-RfRecoveryState($Config, $Run) {
    $actual = @(Get-RfManaged $Config); $a = Get-RfIndex $actual
    $original = Get-RfIndex $Run.BeforeManagedFiles; $changed = @{}
    foreach ($op in $Run.Operations) {
        $changed[$op.Path] = $true
        $state = Get-RfFileState (Join-RfPath $Config.ProductionPath $op.Path)
        if ($Run.Status -eq 'Succeeded') {
            if (-not (Test-RfSame $state $op.After)) { Stop-Rf 'RecoveryDrift' $op.Path }
        } elseif (-not (Test-RfSame $state $op.Before) -and -not (Test-RfSame $state $op.After)) { Stop-Rf 'RecoveryDrift' "Third/partial hash at $($op.Path)." }
        if ($null -ne $op.Before) {
            $backup = Join-RfPath (Join-Path $Config.StatePath "runs/$($Run.RunId)/originals") $op.Path
            if (-not (Test-RfSame (Get-RfFileState $backup) $op.Before)) { Stop-Rf 'RecoveryDataInvalid' $op.Path }
        }
    }
    foreach ($p in $original.Keys) {
        if (-not $changed.ContainsKey($p) -and (-not $a.ContainsKey($p) -or -not (Test-RfSame $original[$p] $a[$p]))) { Stop-Rf 'RecoveryDrift' $p }
    }
    foreach ($p in $a.Keys) { if (-not $original.ContainsKey($p) -and -not $changed.ContainsKey($p)) { Stop-Rf 'RecoveryDrift' "Unexpected managed file $p" } }
}
function Get-RfPausePath($Config, $Path, $PackagePath = '') {
    if ([string]::IsNullOrWhiteSpace($Path)) { Stop-Rf 'InvalidTestProbe' 'PauseSignalPath is required when pausing a test process.' }
    $full = Get-RfFullPath $Path
    foreach ($root in @($Config.ProductionPath, $Config.StatePath, $PackagePath) | Where-Object { $_ }) {
        if (Test-RfUnder $full $root) { Stop-Rf 'InvalidTestProbe' 'Test signal must be outside application, state and package roots.' }
    }
    Assert-RfSafePath -Path $full
    if (Test-Path -LiteralPath $full) { Stop-Rf 'InvalidTestProbe' 'Use a fresh test signal path.' }
    return $full
}
function Suspend-RfTestProcess($SignalPath, $Run) {
    # Explicit fault-test seam: the test harness kills this child after seeing a durable signal.
    Write-RfJson $SignalPath @{ RunId=$Run.RunId; ProcessId=$PID; Phase=$Run.Status }
    while ($true) { [Threading.Thread]::Sleep(1000) }
}
function Abort-RfUnappliedRun($Config, $Run) {
    if ($Run.StartupAttempted -or @($Run.Operations | Where-Object { $_.State -ne 'Pending' }).Count -gt 0) { Stop-Rf 'UnsafePreparation' 'Application operations already began.' }
    Assert-RfInventoryEqual $Run.BeforeManagedFiles (Get-RfManaged $Config) 'Drift'
    if ((Get-RfCanonical (Read-RfBaseline $Config)) -cne (Get-RfCanonical $Run.BaselineBefore)) { Stop-Rf 'BaselineChanged' 'Cannot abort changed baseline.' }
    Set-RfServices $Config $Run $true
    Set-RfPhase $Config $Run 'Aborted'
    Write-RfReport $Config $Run
}
function Restore-RfRun($Config, $Run, $Automatic, $FailAfterFiles = [int]::MaxValue, $PauseAfterFiles = -1, $PauseSignalPath = '') {
    if (-not $Run.BackupsComplete) { Stop-Rf 'RecoveryDataIncomplete' 'Snapshot/originals were not completed; manual intervention required.' }
    Assert-RfRecoveryState $Config $Run
    Set-RfPhase $Config $Run 'Recovering'
    Set-RfServices $Config $Run $false
    $restoredCount = 0
    foreach ($op in $Run.Operations) {
        $target = Join-RfPath $Config.ProductionPath $op.Path
        # Recheck immediately before each write, including a resumed recovery.
        $state = Get-RfFileState $target
        if (-not (Test-RfSame $state $op.Before) -and -not (Test-RfSame $state $op.After)) { Stop-Rf 'RecoveryDrift' $op.Path }
        $op.RecoveryState = 'Intent'; Save-RfRun $Config $Run
        if ($null -eq $op.Before) { if ([IO.File]::Exists($target)) { [IO.File]::Delete($target) } }
        else {
            $backup = Join-RfPath (Join-Path $Config.StatePath "runs/$($Run.RunId)/originals") $op.Path
            Copy-RfFile $backup $target $op.Metadata
        }
        if (-not (Test-RfSame (Get-RfFileState $target) $op.Before)) { Stop-Rf 'RecoveryVerificationFailed' $op.Path }
        $op.RecoveryState = 'Done'; Save-RfRun $Config $Run
        $restoredCount++
        if ($restoredCount -eq $PauseAfterFiles) { Suspend-RfTestProcess $PauseSignalPath $Run }
        if ($restoredCount -ge $FailAfterFiles) { Stop-Rf 'InjectedRecoveryFailure' "After $restoredCount restored files." }
    }
    Assert-RfInventoryEqual $Run.BeforeManagedFiles (Get-RfManaged $Config) 'RecoveryVerificationFailed'
    Write-RfJson (Join-Path $Config.StatePath 'baseline.json') $Run.BaselineBefore
    Set-RfServices $Config $Run $true
    if ($Config.HealthCheck.Fail) {
        Set-RfServices $Config $Run $false
        Stop-Rf 'RecoveryHealthFailed' 'Simulated original-version health check failed; services left stopped.'
    }
    $status = 'Recovered'; if ($Automatic) { $status = 'AutoRecovered' }
    Set-RfPhase $Config $Run $status
    Write-RfReport $Config $Run
}
function Invoke-RfDeployment {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$PlanPath,
        [switch]$ConfirmExecution,
        [ValidateRange(0,2147483647)][int]$FailAfterFiles = 2147483647,
        [switch]$FailHealthCheck,
        [switch]$FailServiceStop,
        [switch]$FailServiceStart,
        [switch]$PauseAtPreparation,
        [ValidateRange(-1,2147483647)][int]$PauseAfterFiles = -1,
        [string]$PauseSignalPath
    )
    if (-not $ConfirmExecution) { Stop-Rf 'ConfirmationRequired' 'Supply -ConfirmExecution after reviewing the plan.' }
    $plan = Read-RfJson (Get-RfFullPath $PlanPath)
    if (-not $plan.ContainsKey('PlanSha256')) { Stop-Rf 'InvalidPlan' 'Missing plan digest.' }
    $digest = $plan.PlanSha256; $plan.Remove('PlanSha256')
    if ((Get-RfTextHash (Get-RfCanonical $plan)) -ne $digest) { Stop-Rf 'PlanChanged' 'Plan digest differs.' }
    $c = Read-RfConfig $plan.TargetConfigPath; $lock = Enter-RfLock $c; $run = $null
    try {
        Assert-RfComplete $c
        # Re-read config under lock, then recompute the complete approved plan.
        $c = Read-RfConfig $plan.TargetConfigPath
        if ($PauseAfterFiles -ge 0 -or $PauseAtPreparation) { $PauseSignalPath = Get-RfPausePath $c $PauseSignalPath $plan.PackagePath }
        $fresh = Get-RfPlanData $plan.PackagePath $c
        if ((Get-RfCanonical $fresh) -cne (Get-RfCanonical $plan)) { Stop-Rf 'PlanStale' 'Package, target definition, baseline or actual files changed; produce a new plan.' }
        if ($plan.NoOp) { return [pscustomobject]@{ Status = 'NoOp'; TargetId = $c.TargetId; Version = $plan.TargetVersion; RunId = $null } }
        $id = [guid]::NewGuid().ToString()
        $runRoot = Join-Path $c.StatePath "runs/$id"
        [void][IO.Directory]::CreateDirectory($runRoot)
        $initial = Get-RfServices $c
        $previous = Get-RfCurrent $c
        $previousRunId = $null; if ($null -ne $previous) { $previousRunId = $previous.RunId }
        $run = [ordered]@{
            SchemaVersion = 1; ToolVersion = $script:RfToolVersion; RunId = $id; TargetId = $c.TargetId; PreviousRunId = $previousRunId
            ProductionPath = $c.ProductionPath; PackagePath = $plan.PackagePath; TargetConfigSha256 = $plan.TargetConfigSha256; PlanSha256 = $digest
            Status = 'Preparing'; CreatedUtc = [DateTime]::UtcNow.ToString('o'); UpdatedUtc = [DateTime]::UtcNow.ToString('o')
            Operator = [Environment]::UserName; SourceVersion = $plan.SourceVersion; TargetVersion = $plan.TargetVersion
            BaselineBefore = Read-RfBaseline $c; BaselineAfter = $null; BeforeManagedFiles = $plan.ActualManagedFiles
            DesiredFiles = $plan.DesiredFiles; InitialServices = $initial; Services = @{}; ServiceEvents = @(); ServiceIntent = $null
            BackupsComplete = $false; StartupAttempted = $false; Operations = @(); SnapshotMetadata = @(); Error = $null
        }
        foreach ($n in $initial.Keys) { $run.Services[$n] = $initial[$n] }
        foreach ($change in $plan.Changes) {
            $op = @{}; foreach ($key in $change.Keys) { $op[$key] = $change[$key] }
            $op['State'] = 'Pending'; $op['RecoveryState'] = 'Pending'; $op['Metadata'] = $null
            $run.Operations += $op
        }
        Save-RfRun $c $run
        Write-RfJson (Join-Path $c.StatePath 'current.json') @{ SchemaVersion = 1; RunId = $id; TargetId = $c.TargetId }
        # A self-contained recovery record does not rely on the delivery package.
        Write-RfJson (Join-Path $runRoot 'plan.json') $plan
        Save-RfRecoveryTools $c $runRoot
        if ($PauseAtPreparation) { Suspend-RfTestProcess $PauseSignalPath $run }
        Set-RfPhase $c $run 'Stopping'; Set-RfServices $c $run $false ([bool]$FailServiceStop)
        Set-RfPhase $c $run 'BackingUp'
        Assert-RfInventoryEqual $run.BeforeManagedFiles (Get-RfManaged $c) 'Drift'
        foreach ($f in $run.BeforeManagedFiles) {
            $source = Join-RfPath $c.ProductionPath $f.Path
            $metadata = @{ Path = $f.Path; Sddl = Get-RfAclMetadata $source; LastWriteUtc = [IO.File]::GetLastWriteTimeUtc($source).ToString('o'); Attributes = [int][IO.File]::GetAttributes($source) }
            $run.SnapshotMetadata += $metadata
            $snapshot = Join-RfPath (Join-Path $runRoot 'snapshot') $f.Path
            Copy-RfFile $source $snapshot
            if (-not (Test-RfSame (Get-RfFileState $snapshot) $f)) { Stop-Rf 'BackupVerificationFailed' $f.Path }
        }
        foreach ($op in $run.Operations) {
            if ($null -ne $op.Before) {
                $op.Metadata = @($run.SnapshotMetadata | Where-Object { $_.Path -eq $op.Path })[0]
                $original = Join-RfPath (Join-Path $runRoot 'originals') $op.Path
                Copy-RfFile (Join-RfPath (Join-Path $runRoot 'snapshot') $op.Path) $original
                if (-not (Test-RfSame (Get-RfFileState $original) $op.Before)) { Stop-Rf 'BackupVerificationFailed' $op.Path }
            }
        }
        $run.BackupsComplete = $true; Set-RfPhase $c $run 'Applying'
        $count = 0
        if ($PauseAfterFiles -eq 0) { Suspend-RfTestProcess $PauseSignalPath $run }
        if ($FailAfterFiles -eq 0) { Stop-Rf 'InjectedApplicationFailure' 'Before first operation.' }
        foreach ($op in $run.Operations) {
            if (-not (Test-RfSame (Get-RfFileState $op.TargetPath) $op.Before)) { Stop-Rf 'Drift' $op.Path }
            if ($null -ne $op.After -and -not (Test-RfSame (Get-RfFileState $op.SourcePath) $op.After)) { Stop-Rf 'PackageChanged' $op.Path }
            $op.State = 'Intent'; Save-RfRun $c $run
            if ($op.Kind -eq 'Removed') { [IO.File]::Delete($op.TargetPath) }
            else {
                Copy-RfFile $op.SourcePath $op.TargetPath
                if ($null -ne $op.Metadata) { Set-RfAclMetadata $op.TargetPath $op.Metadata.Sddl }
            }
            if (-not (Test-RfSame (Get-RfFileState $op.TargetPath) $op.After)) { Stop-Rf 'ApplyVerificationFailed' $op.Path }
            $op.State = 'Done'; Save-RfRun $c $run
            $count++
            if ($count -eq $PauseAfterFiles) { Suspend-RfTestProcess $PauseSignalPath $run }
            if ($count -ge $FailAfterFiles) { Stop-Rf 'InjectedApplicationFailure' "After $count file operations." }
        }
        # Expected managed inventory also includes untouched untracked files.
        $expected = @($run.BeforeManagedFiles | Where-Object { -not (Test-RfScope $_.Path @($run.Operations | ForEach-Object { $_.Path })) })
        $expected += @($run.Operations | Where-Object { $null -ne $_.After } | ForEach-Object { $_.After })
        Assert-RfInventoryEqual $expected (Get-RfManaged $c) 'ApplyVerificationFailed'
        $run.StartupAttempted = $true; Set-RfPhase $c $run 'Starting'; Set-RfServices $c $run $true ([bool]$FailServiceStart)
        Set-RfPhase $c $run 'Verifying'
        if ($FailHealthCheck -or $c.HealthCheck.Fail) { Stop-Rf 'HealthCheckFailed' 'Simulated health check failed after startup.' }
        $b = [ordered]@{ SchemaVersion = 1; TargetId = $c.TargetId; ProductionPath = $c.ProductionPath; Version = $plan.TargetVersion; Commit = $plan.Package.Commit; LatestRunId = $id; Files = $plan.DesiredFiles }
        # Intent remains incomplete until both baseline and journal are committed.
        $run.BaselineAfter = $b
        Set-RfPhase $c $run 'Committing'
        Write-RfJson (Join-Path $c.StatePath 'baseline.json') $b
        Set-RfPhase $c $run 'Succeeded'
        Write-RfReport $c $run
        Save-RfArchive $c $run
        return [pscustomobject]$run
    } catch {
        $failure = $_
        if ([string]$failure -match 'RF_PersistenceFailed:') {
            Stop-Rf 'NeedsIntervention' "$failure; no further automatic mutations attempted. Inspect the durable journal."
        }
        if ($null -ne $run) {
            try {
                $run.Error = [string]$failure
                if (-not $run.StartupAttempted -and $run.BackupsComplete) {
                    Set-RfPhase $c $run 'ApplicationFailed'
                    Restore-RfRun $c $run $true
                } elseif (-not $run.StartupAttempted -and @($run.Operations | Where-Object { $_.State -ne 'Pending' }).Count -eq 0) {
                    Abort-RfUnappliedRun $c $run
                } else {
                    Set-RfPhase $c $run 'NeedsIntervention'; Set-RfServices $c $run $false
                    Write-RfReport $c $run
                }
            } catch {
                # Never continue file mutations after a failed durable write or unsafe recovery.
                $secondary = $_
                try { $run.Error = "$failure | Recovery/intervention: $secondary"; Set-RfPhase $c $run 'NeedsIntervention' } catch { }
                Stop-Rf 'NeedsIntervention' "$failure | $secondary; inspect state/run records."
            }
        }
        throw $failure
    } finally { $lock.Dispose() }
}
function Invoke-RfRecovery {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$TargetConfigPath, [switch]$ConfirmExecution,
        [ValidateRange(1,2147483647)][int]$FailAfterFiles = [int]::MaxValue,
        [ValidateRange(-1,2147483647)][int]$PauseAfterFiles = -1, [string]$PauseSignalPath
    )
    if (-not $ConfirmExecution) { Stop-Rf 'ConfirmationRequired' 'Supply -ConfirmExecution to restore the latest eligible run.' }
    $c = Read-RfConfig $TargetConfigPath; $lock = Enter-RfLock $c; $run = $null
    try {
        $indexed = Get-RfCurrent $c
        $run = Get-RfRecoveryCandidate $c
        if ($null -eq $run -or $run.Status -in @('Recovered','AutoRecovered','Aborted')) { Stop-Rf 'RecoveryNotEligible' 'No latest unrecovered operation.' }
        if (@(Get-RfPendingRuns $c | Where-Object { $_.RunId -ne $run.RunId }).Count -gt 0) { Stop-Rf 'IncompleteRun' 'An orphan unfinished run needs resolution before recovery of the indexed run.' }
        if ($run.SchemaVersion -ne 1 -or $run.ToolVersion -ne $script:RfToolVersion -or $run.TargetId -cne $c.TargetId -or $run.ProductionPath -ne $c.ProductionPath) { Stop-Rf 'IncompatibleRecovery' 'Recovery schema/tool/target mismatch.' }
        if ($run.TargetConfigSha256 -ne (Get-RfHash $c._ConfigPath)) { Stop-Rf 'ConfigChanged' 'Recovery requires the unchanged target definition.' }
        if ($PauseAfterFiles -ge 0) { $PauseSignalPath = Get-RfPausePath $c $PauseSignalPath $run.PackagePath }
        $baseline = Read-RfBaseline $c
        if ($run.Status -eq 'Succeeded' -and $baseline.LatestRunId -ne $run.RunId) { Stop-Rf 'RecoveryNotEligible' 'Run was superseded.' }
        # During commit, baseline may be old or new; no third recorded baseline accepted.
        $isOld = (Get-RfCanonical $baseline) -ceq (Get-RfCanonical $run.BaselineBefore)
        $isNew = $null -ne $run.BaselineAfter -and (Get-RfCanonical $baseline) -ceq (Get-RfCanonical $run.BaselineAfter)
        if (-not $isOld -and -not $isNew) { Stop-Rf 'BaselineChanged' 'Baseline is not a known state of the latest run.' }
        if ($null -ne $indexed -and $indexed.RunId -ne $run.RunId) {
            # Commit the eligible index before restoration so an interrupted recovery resumes it.
            Write-RfJson (Join-Path $c.StatePath 'current.json') @{ SchemaVersion=1; TargetId=$c.TargetId; RunId=$run.RunId }
        }
        Restore-RfRun $c $run $false $FailAfterFiles $PauseAfterFiles $PauseSignalPath
        return [pscustomobject]$run
    } catch {
        $failure = $_
        if ($null -ne $run -and $run.Status -eq 'Recovering' -and [string]$failure -notmatch 'RF_PersistenceFailed:') {
            try { Set-RfServices $c $run $false; $run.Error = [string]$failure; Set-RfPhase $c $run 'NeedsIntervention' } catch { }
        }
        throw $failure
    } finally { $lock.Dispose() }
}
function Get-RfStatus {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$TargetConfigPath)
    $c = Read-RfConfig $TargetConfigPath; $lock = Enter-RfLock $c
    try {
        $run = Get-RfCurrent $c; $b = $null
        if ([IO.File]::Exists((Join-Path $c.StatePath 'baseline.json'))) { $b = Read-RfBaseline $c }
        return [pscustomobject]@{ TargetId = $c.TargetId; Baseline = $b; CurrentRun = $run; PendingRuns = @(Get-RfPendingRuns $c); Services = Get-RfServices $c; Mode = 'Simulated' }
    } finally { $lock.Dispose() }
}
Export-ModuleMember -Function New-RfManifest, New-RfBaseline, New-RfPlan, Invoke-RfDeployment, Invoke-RfRecovery, Get-RfStatus, Get-RfToolVersion, Assert-RfSafePath, Assert-RfRelativePath, Resolve-RfPreparation
