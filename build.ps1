$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$source = Join-Path $PSScriptRoot 'extension'
$package = Join-Path $PSScriptRoot 'AseLaps.aseprite-extension'
$pending = Join-Path $PSScriptRoot 'AseLaps.aseprite-extension.tmp'

if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending }
[System.IO.Compression.ZipFile]::CreateFromDirectory($source, $pending)
$archive = [System.IO.Compression.ZipFile]::OpenRead($pending)
try {
    $manifest = $archive.GetEntry('package.json')
    if (-not $manifest) { throw 'The archive root must contain package.json.' }
    $reader = [System.IO.StreamReader]::new($manifest.Open())
    try { $definition = $reader.ReadToEnd() | ConvertFrom-Json }
    finally { $reader.Dispose() }
    if ($definition.name -ne 'AseLaps') { throw 'Unexpected extension name.' }
    foreach ($script in $definition.contributes.scripts) {
        $path = $script.path -replace '^\./', ''
        if (-not $archive.GetEntry($path)) { throw "Missing extension script $path" }
    }
}
finally { $archive.Dispose() }
Move-Item -LiteralPath $pending -Destination $package -Force
Get-Item -LiteralPath $package
