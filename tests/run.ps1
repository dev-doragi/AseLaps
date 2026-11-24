param(
    [Parameter(Mandatory)][string]$Aseprite,
    [string]$FFmpeg
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $root ('.test-work\run-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$Aseprite = (Get-Item -LiteralPath $Aseprite).FullName
if ($FFmpeg) { $FFmpeg = (Get-Item -LiteralPath $FFmpeg).FullName }
foreach ($test in @(@{Name='probe'; Marker='ASELAPS_PROBE_OK'}, @{Name='sampled'; Marker='ASELAPS_SAMPLED_OK'}, @{Name='v2'; Marker='ASELAPS_V2_OK'}, @{Name='v4'; Marker='ASELAPS_V4_OK'})) {
    $argsList = @('--noinapp', '-b', '--script-param', "root=$root", '--script-param', "work=$work\$($test.Name)")
    if ($FFmpeg) { $argsList += @('--script-param', "ffmpeg=$FFmpeg") }
    $argsList += @('--script', (Join-Path $PSScriptRoot "$($test.Name).lua"))
    $result = & $Aseprite @argsList | ForEach-Object { $_ }
    $result | Out-Host
    if ($LASTEXITCODE -ne 0 -or $result -notcontains $test.Marker) {
        throw "Aseprite test $($test.Name) failed: $work"
    }
}
Write-Host "Test workspace: $work"
