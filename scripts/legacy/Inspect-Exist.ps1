param(
    [Parameter(Mandatory=$true)][string]$SourcesRoot,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$SourcesRoot = Get-LegacyAbsolute $SourcesRoot
$OutputPath = Get-LegacyAbsolute $OutputPath
Assert-LegacyDisjoint -OutputRoot $OutputPath -InputRoots @((Join-Path $SourcesRoot 'exist-source-subset'))
if (Test-Path -LiteralPath $OutputPath) { throw 'Static inspection output must be new.' }
$metadata = Get-Content (Join-Path $SourcesRoot 'acquisition.json') -Raw | ConvertFrom-Json
$root = Join-Path $SourcesRoot 'exist-source-subset'
$records = @($metadata.Sources | Where-Object { $_.Project -eq 'eXist' })
if ($records.Count -ne 13 -or @($records | Where-Object { $_.Commit -cne '3be6286d3085626fc9a7fd711be12f424367298f' }).Count -ne 0) { throw 'Unexpected eXist source subset.' }
foreach ($record in $records) {
    $path = [IO.Path]::GetFullPath((Join-Path $root $record.Path))
    if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe source metadata path.' }
    if ((Get-FileHash -LiteralPath $path).Hash -ne $record.Sha256) { throw "Acquired source changed: $($record.Path)" }
}
function Read-SafeXml([string]$Path) {
    $settings = New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path,$settings)
    try { $doc = New-Object Xml.XmlDocument; $doc.XmlResolver=$null; $doc.Load($reader); return ,$doc }
    finally { $reader.Dispose() }
}
$wrapper = Read-SafeXml (Join-Path $root 'tools/yajsw/build.xml')
$implementation = Read-SafeXml (Join-Path $root 'build/scripts/build-impl.xml')
$batch = Get-Content (Join-Path $root 'build.bat') -Raw
$config = Get-Content (Join-Path $root 'tools/yajsw/conf/wrapper.conf.in') -Raw
$checks = @{
    AcquiredFilesUnchanged=$true
    BatchDelegatesToAnt=$batch.Contains('org.apache.tools.ant.launch.Launcher')
    NoDirectJavacCommand=($batch -notmatch '(?mi)^\s*javac\s')
    WrapperCompilesLooseClasses=(@($wrapper.SelectNodes('//javac') | Where-Object { $_.GetAttribute('destdir') -eq '${classes}' }).Count -gt 0)
    WrapperPrepareDeletesLogs=(@($wrapper.SelectNodes('//target[@name="prepare"]/delete') | Where-Object { $_.GetAttribute('dir') -eq '${logs}' }).Count -gt 0)
    WrapperPrepareDeletesWork=(@($wrapper.SelectNodes('//target[@name="prepare"]/delete') | Where-Object { $_.GetAttribute('dir') -eq '${work}' }).Count -gt 0)
    NoActiveScmDependencyInTemplate=($config -notmatch '(?m)^\s*wrapper\.ntservice\.dependency\.\d+\s*=')
}
if (@($checks.Values | Where-Object { -not $_ }).Count -gt 0) { throw 'Pinned source no longer matches the inspected characteristics.' }
$targets = @($implementation.SelectNodes('//target') | ForEach-Object { @{Name=$_.GetAttribute('name');Depends=$_.GetAttribute('depends')} })
$deletes = @($implementation.SelectNodes('//delete') | ForEach-Object { @{Directory=$_.GetAttribute('dir');File=$_.GetAttribute('file')} })
$result = @{SchemaVersion=1;Project='eXist-db 3.6.1';Commit='3be6286d3085626fc9a7fd711be12f424367298f';SourceScope='13-file subset, not a buildable or deployable checkout';Checks=$checks;CheckCount=$checks.Count;ParsedXmlFiles=2;ImplementationTargets=$targets;ImplementationDeleteTasks=$deletes;LegacyBuildExecuted=$false;RealServicesOperated=$false;BuildStatus='Blocked: reviewed Java8 build environment and full dependency closure required';DeploymentStatus='Blocked: real service mode unsupported by current core';Result='Static checks passed only'}
New-Item -ItemType Directory -Path $OutputPath | Out-Null
$result | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $OutputPath 'inspection-results.json') -Encoding UTF8
Write-Host "eXist static inspection: $($checks.Count) checks passed, 2 XML files parsed with external entities disabled. No build or service operation."
