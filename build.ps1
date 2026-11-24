$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$source = Join-Path $PSScriptRoot 'extension'
$package = Join-Path $PSScriptRoot 'AseLaps.aseprite-extension'
$pending = Join-Path $PSScriptRoot 'AseLaps.aseprite-extension.tmp'

if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending }
$files = @('package.json','init.lua','ui.lua','recorder.lua','store.lua','history.lua','codec.lua','export.lua','windows.ps1','AseLaps.cmd','RawEncoder.cs','FolderPicker.cs')
$version = (Get-Content -Raw -LiteralPath (Join-Path $source 'package.json') | ConvertFrom-Json).version
if ($version -notmatch '^\d+\.\d+\.\d+(-[A-Za-z0-9.]+)?$') { throw 'Invalid package version.' }
$created = [System.IO.Compression.ZipFile]::Open($pending, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in $files) {
        if ($name -eq 'ui.lua') {
            $entry = $created.CreateEntry($name)
            $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
            try { $writer.Write([IO.File]::ReadAllText((Join-Path $source $name)).Replace('@ASELAPS_VERSION@', $version)) }
            finally { $writer.Dispose() }
        }
        else { [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($created, (Join-Path $source $name), $name) | Out-Null }
    }
    foreach ($name in @('README.md','LICENSE')) {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($created, (Join-Path $PSScriptRoot $name), $name) | Out-Null
    }
}
finally { $created.Dispose() }
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
