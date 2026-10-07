# Helper functions used only by the legacy-source exercise; upstream scripts are never invoked.
function Get-LegacyAbsolute([string]$Path) {
    return [IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))
}
function Assert-LegacyDisjoint([string]$OutputRoot, [string[]]$InputRoots) {
    $out = (Get-LegacyAbsolute $OutputRoot).TrimEnd('\','/')
    foreach ($inputRoot in $InputRoots) {
        $input = (Get-LegacyAbsolute $inputRoot).TrimEnd('\','/')
        if ($out.Equals($input, [StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($input + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $input.StartsWith($out + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Exercise output must not overlap any input source/build directory.'
        }
    }
}
function Get-LegacyDownload([string]$Url, [string]$OutputPath, [long]$MaxBytes) {
    if (Test-Path -LiteralPath $OutputPath) { throw "Download output exists: $OutputPath" }
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($OutputPath)) -Force | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $request = [Net.WebRequest]::Create($Url)
    $request.Timeout = 60000
    $response = $request.GetResponse()
    $inputStream = $null; $outputStream = $null
    try {
        if ($response.ContentLength -gt $MaxBytes) { throw 'Download exceeds the exercise size limit.' }
        $inputStream = $response.GetResponseStream()
        $outputStream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        $buffer = New-Object byte[] 65536
        $total = 0L
        while (($read = $inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $total += $read
            if ($total -gt $MaxBytes) { throw 'Download exceeds the exercise size limit.' }
            $outputStream.Write($buffer,0,$read)
        }
        $outputStream.Flush($true)
    } finally {
        if ($null -ne $outputStream) { $outputStream.Dispose() }
        if ($null -ne $inputStream) { $inputStream.Dispose() }
        $response.Close()
    }
}
