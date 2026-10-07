param(
    [Parameter(Mandatory=$true)][string]$BuildPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$BuildPath = Get-LegacyAbsolute $BuildPath
$OutputPath = Get-LegacyAbsolute $OutputPath
Assert-LegacyDisjoint -OutputRoot $OutputPath -InputRoots @($BuildPath)
if (Test-Path -LiteralPath $OutputPath) { throw 'Probe output must be new.' }
$repo = Get-LegacyAbsolute (Join-Path $PSScriptRoot '../..')
$classes = Join-Path $BuildPath 'app/classes'
$plugins = Join-Path $BuildPath 'app/plugins'
$files = @(Get-ChildItem $plugins -File -Recurse)
if ($files.Count -ne 1 -or $files[0].Name -cne 'JavaScriptEvaluator.class') { throw 'Probe permits only the reviewed compiled plugin, no extra JARs or plugins.' }
Import-Module (Join-Path $repo 'src/ReleaseFlow.psm1') -Force
New-Item -ItemType Directory -Path $OutputPath | Out-Null
New-RfManifest -Root (Join-Path $BuildPath 'app') -OutputPath (Join-Path $OutputPath 'input-manifest.json') | Out-Null
$probeSource = Join-Path $repo 'examples/legacy-java/imagej/PluginLoadProbe.java'
$compiler = (Get-Command javac -CommandType Application).Source
$java = (Get-Command java -CommandType Application).Source
$classpath = $OutputPath + [IO.Path]::PathSeparator + $classes
$saved = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $compileLog = & $compiler '-proc:none' '--release' '8' '-cp' $classes '-d' $OutputPath $probeSource 2>&1
    $compileExit = $LASTEXITCODE
    @($compileLog | ForEach-Object { [string]$_ }) | Set-Content (Join-Path $OutputPath 'compile.log') -Encoding UTF8
    if ($compileExit -ne 0) { throw "Probe compilation failed: $compileExit" }
    $runLog = & $java '-Djava.awt.headless=true' '-cp' $classpath 'PluginLoadProbe' $plugins 2>&1
    $runExit = $LASTEXITCODE
    @($runLog | ForEach-Object { [string]$_ }) | Set-Content (Join-Path $OutputPath 'probe.log') -Encoding UTF8
    if ($runExit -ne 0) { throw "Reviewed classloader probe failed: $runExit" }
} finally { $ErrorActionPreference = $saved }
@{SchemaVersion=1;Result='Passed';CompileExit=$compileExit;RunExit=$runExit;UpstreamLoaderExecuted=$true;PluginInitializationRequested=$false;PluginInstantiated=$false;PluginRunInvoked=$false;GUIStarted=$false;RealServicesOperated=$false;Scope='Reviewed upstream loader constructor and non-initializing class resolution only'} | ConvertTo-Json | Set-Content (Join-Path $OutputPath 'probe-results.json') -Encoding UTF8
$runLog | ForEach-Object { Write-Host ([string]$_) }
