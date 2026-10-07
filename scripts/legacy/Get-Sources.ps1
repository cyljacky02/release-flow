param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$Root = Get-LegacyAbsolute $Root
if (Test-Path -LiteralPath $Root) { throw 'Use a new exercise root. Existing downloads are never reset.' }
$repositoryRoot = Get-LegacyAbsolute (Join-Path $PSScriptRoot '../..')
$pins = Get-Content (Join-Path $repositoryRoot 'examples/legacy-java/sources.json') -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $Root | Out-Null
$records = @()
# eXist: only a clearly labelled source subset; no JARs or installable distribution.
foreach ($relative in $pins.Exist.Files) {
    $url = "https://raw.githubusercontent.com/$($pins.Exist.Repository)/$($pins.Exist.Commit)/$relative"
    $path = Join-Path $Root "exist-source-subset/$relative"
    Get-LegacyDownload -Url $url -OutputPath $path -MaxBytes 2097152
    $records += @{Project='eXist';Repository=$pins.Exist.Repository;Commit=$pins.Exist.Commit;Path=$relative;Sha256=(Get-FileHash $path).Hash;Url=$url}
}
# ImageJ: bounded pinned source archive, extracted without running its auto-launching BAT.
$url = "https://codeload.github.com/$($pins.ImageJ.Repository)/zip/$($pins.ImageJ.Commit)"
$archive = Join-Path $Root 'imagej-source.zip'
Get-LegacyDownload -Url $url -OutputPath $archive -MaxBytes 41943040
$hash = (Get-FileHash $archive).Hash
& (Join-Path $repositoryRoot 'scripts/Deliver.ps1') -ArchivePath $archive -ExpectedSha256 $hash -DestinationPath (Join-Path $Root 'imagej-extracted')
$source = Join-Path $Root "imagej-extracted/ImageJ-$($pins.ImageJ.Commit)"
if (-not (Test-Path (Join-Path $source 'compile.bat'))) { throw 'Unexpected pinned ImageJ archive layout.' }
$records += @{Project='ImageJ';Repository=$pins.ImageJ.Repository;Commit=$pins.ImageJ.Commit;Path='source archive';Sha256=$hash;Url=$url}
$metadata = @{SchemaVersion=1;Sources=$records;ImageJSourcePath=$source;ExistScope='source subset only; not built';UpstreamCodeExecuted=$false}
$metadata | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $Root 'acquisition.json') -Encoding UTF8
Write-Host "Pinned source acquisition complete: $Root. No upstream code executed."
