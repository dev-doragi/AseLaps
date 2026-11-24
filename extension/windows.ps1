param(
    [Parameter(Mandatory)][ValidateSet('export', 'browse', 'open', 'check')][string]$Action,
    [Parameter(Mandatory)][ValidatePattern('^AseLaps-[0-9]+_[0-9]+$')][string]$JobName
)

$ErrorActionPreference = 'Stop'
$job = Join-Path ([IO.Path]::GetTempPath()) $JobName
$request = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $job 'request.json') | ConvertFrom-Json

switch ($Action) {
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
