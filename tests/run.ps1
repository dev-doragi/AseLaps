param(
    [Parameter(Mandatory)][string]$Aseprite,
    [string]$FFmpeg,
    [string]$SourceRoot,
    [int]$TimeoutSeconds = 180
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $SourceRoot) { $SourceRoot = $root }
$work = Join-Path $root ('.test-work\run-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
$profile = Join-Path $work 'profile'
New-Item -ItemType Directory -Force -Path $profile | Out-Null
$Aseprite = (Get-Item -LiteralPath $Aseprite).FullName
if ($FFmpeg) { $FFmpeg = (Get-Item -LiteralPath $FFmpeg).FullName }
$cases = @('probe', 'sampled', 'v2', 'v4', 'release', 'stress')
foreach ($name in $cases) {
    $testFile = Join-Path $PSScriptRoot "$name.lua"
    if (-not (Test-Path -LiteralPath $testFile)) { throw "Missing test: $testFile" }
    $testWork = Join-Path $work $name
    New-Item -ItemType Directory -Force -Path $testWork | Out-Null
    $start = [Diagnostics.ProcessStartInfo]::new($Aseprite)
    $start.WorkingDirectory = Split-Path -Parent $Aseprite
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['ASEPRITE_USER_FOLDER'] = $profile
    foreach ($argument in @('--noinapp', '-b', '--script-param', "root=$SourceRoot", '--script-param', "work=$testWork")) { $start.ArgumentList.Add($argument) }
    if ($FFmpeg) { $start.ArgumentList.Add('--script-param'); $start.ArgumentList.Add("ffmpeg=$FFmpeg") }
    $start.ArgumentList.Add('--script'); $start.ArgumentList.Add($testFile)
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
    $output = $stdout.GetAwaiter().GetResult()
    $errors = $stderr.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $testWork 'stdout.log'), $output)
    [IO.File]::WriteAllText((Join-Path $testWork 'stderr.log'), $errors)
    $exitCode = $process.ExitCode
    [IO.File]::WriteAllText((Join-Path $testWork 'result.json'), (@{exitCode=$exitCode; timedOut=$timedOut} | ConvertTo-Json))
    $process.Dispose()
    Write-Host $output
    $marker = 'ASELAPS_' + $name.ToUpperInvariant() + '_OK'
    if ($timedOut -or $exitCode -ne 0 -or -not ($output -split '\r?\n' -contains $marker)) {
        throw "Test $name failed (exit=$exitCode, timeout=$timedOut). Logs: $testWork"
    }
}
Write-Host "Test workspace: $work"
