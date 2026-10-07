param(
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$CompilerPath = 'javac'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$SourcePath = Get-LegacyAbsolute $SourcePath
$OutputPath = Get-LegacyAbsolute $OutputPath
Assert-LegacyDisjoint -OutputRoot $OutputPath -InputRoots @($SourcePath)
if (Test-Path -LiteralPath $OutputPath) { throw 'Use a new build output; never compile in the acquired source tree.' }
$expected = @('javac ij\ImageJ.java','javac ij\plugin\*.java','javac ij\plugin\filter\*.java','javac ij\plugin\frame\*.java','java ij.ImageJ')
$batch = @(Get-Content (Join-Path $SourcePath 'compile.bat') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if (($batch -join "`n") -cne ($expected -join "`n")) { throw 'Upstream compile.bat differs from the reviewed pin. Review before building.' }
$repo = Get-LegacyAbsolute (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $repo 'src/ReleaseFlow.psm1') -Force
# Validate input paths without loading any upstream .class files.
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
New-RfManifest -Root $SourcePath -OutputPath (Join-Path $OutputPath 'source-manifest.json') | Out-Null
$worktree = Join-Path $OutputPath 'worktree'
New-Item -ItemType Directory -Path $worktree | Out-Null
foreach ($file in Get-ChildItem (Join-Path $SourcePath 'ij') -Filter '*.java' -File -Recurse) {
    $relative = $file.FullName.Substring($SourcePath.Length + 1)
    $dest = Join-Path $worktree $relative
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($dest)) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $dest
}
$pluginSource = Join-Path $SourcePath 'plugins/JavaScriptEvaluator.source'
if (-not (Test-Path -LiteralPath $pluginSource)) { throw 'Pinned external plugin source is missing.' }
New-Item -ItemType Directory -Path (Join-Path $worktree 'plugins') -Force | Out-Null
Copy-Item -LiteralPath $pluginSource -Destination (Join-Path $worktree 'plugins/JavaScriptEvaluator.java')
$compiler = (Get-Command $CompilerPath -CommandType Application -ErrorAction Stop).Source
$attempt = @{SchemaVersion=1;Project='ImageJ';Version='1.51u';Compiler=$compiler;Scope='Compile only; no upstream BAT, JVM application or plugin executed';Adaptations=@('JDK compiler --release 8','Annotation processing disabled','Explicit source enumeration','No java ij.ImageJ launch','Exclude upstream prebuilt .class','Compile genuine JavaScriptEvaluator.source separately as .java');Stages=@();Status='Running'}
$groups = @(@{Pattern='ij/ImageJ.java'},@{Pattern='ij/plugin/*.java'},@{Pattern='ij/plugin/filter/*.java'},@{Pattern='ij/plugin/frame/*.java'},@{Pattern='plugins/JavaScriptEvaluator.java'})
$log = Join-Path $OutputPath 'javac.log'
Push-Location $worktree
try {
    foreach ($group in $groups) {
        $sources = @(Get-ChildItem $group.Pattern -File | ForEach-Object { $_.FullName })
        if ($sources.Count -eq 0) { throw "No sources for $($group.Pattern)" }
        $arguments = @('-proc:none','--release','8','-classpath',$worktree,'-sourcepath',$worktree) + $sources
        $saved = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = & $compiler @arguments 2>&1
            $exitCode = $LASTEXITCODE
        } finally { $ErrorActionPreference = $saved }
        @($output | ForEach-Object { [string]$_ }) | Add-Content $log -Encoding UTF8
        $attempt.Stages += @{Pattern=$group.Pattern;SourceCount=$sources.Count;ExitCode=$exitCode}
        if ($exitCode -ne 0) { throw "ImageJ compiler rejected $($group.Pattern), exit $exitCode. See $log; source remains unmodified." }
    }
    $app = Join-Path $OutputPath 'app'
    foreach ($file in Get-ChildItem $worktree -Filter '*.class' -File -Recurse) {
        $relative = $file.FullName.Substring($worktree.Length + 1)
        if ($relative.Replace('\','/').StartsWith('plugins/')) { $dest = Join-Path $app $relative }
        else { $dest = Join-Path $app ('classes/' + $relative) }
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($dest)) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $dest
    }
    if (-not (Test-Path (Join-Path $app 'classes/ij/ImageJ.class'))) { throw 'Expected genuine compiled ImageJ entry class is missing.' }
    @{SchemaVersion=1;Version='1.51u';Commit='e52a4b2c888ed0170384706b3aa87af1b2f4e5c8'} | ConvertTo-Json | Set-Content (Join-Path $OutputPath 'build.json') -Encoding UTF8
    $attempt.Status = 'Compiled'
    $attempt.ClassCount = @(Get-ChildItem $app -Filter '*.class' -File -Recurse).Count
} catch {
    $attempt.Status = 'Blocked'; $attempt.Error = [string]$_
    throw
} finally {
    Pop-Location
    $attempt | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $OutputPath 'build-attempt.json') -Encoding UTF8
}
Write-Host "Compiled real ImageJ source into $($attempt.ClassCount) loose classes. No application launched."
