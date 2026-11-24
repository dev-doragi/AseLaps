param(
    [Parameter(Mandatory)][ValidateSet('export', 'start', 'worker', 'browse', 'open', 'check')][string]$Action,
    [Parameter(Mandatory)][ValidatePattern('^AseLaps-[0-9]+_[0-9]+$')][string]$JobName
)

$ErrorActionPreference = 'Stop'
$job = Join-Path ([IO.Path]::GetTempPath()) $JobName
$request = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $job 'request.json') | ConvertFrom-Json

switch ($Action) {
    'start' {
        $scriptPath = Join-Path $PSScriptRoot 'windows.ps1'
        $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $scriptPath + '" worker ' + $JobName
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    }
    'worker' {
        try {
            Add-Type -Path (Join-Path $PSScriptRoot 'RawEncoder.cs')
            [AseLapsRawEncoder]::RunJob([string]$request.executable, [string[]]$request.arguments, [string]$request.log, [string]$request.cancel, [string]$request.status)
        }
        catch {
            [IO.File]::WriteAllText([string]$request.log, ($_ | Out-String))
            [IO.File]::WriteAllText([string]$request.status, 'failed')
            exit 1
        }
    }
    'check' {
        & ([string]$request.executable) -version | Out-Null
        exit $LASTEXITCODE
    }
    'export' {
        $executable = [string]$request.executable
        $ffArgs = [string[]]$request.arguments
        Add-Type -Path (Join-Path $PSScriptRoot 'RawEncoder.cs')
        exit [AseLapsRawEncoder]::Run($executable, $ffArgs, [string]$request.log)
    }
    'browse' {
        Add-Type -Path (Join-Path $PSScriptRoot 'FolderPicker.cs')
        $initial = [string]$request.initial
        if (-not $initial -or -not (Test-Path -LiteralPath $initial -PathType Container)) {
            $initial = [string]$request.fallback
        }
        if ($initial -and -not (Test-Path -LiteralPath $initial -PathType Container)) { $initial = '' }
        $selected = [AseLapsFolderPicker]::Choose($initial)
        if ($selected) {
            [IO.File]::WriteAllText((Join-Path $job 'selection.txt'), $selected)
        }
    }
    'open' {
        Invoke-Item -LiteralPath $request.path
    }
}
