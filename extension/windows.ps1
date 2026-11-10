param(
    [Parameter(Mandatory)][ValidateSet('export', 'browse', 'open')][string]$Action,
    [Parameter(Mandatory)][ValidatePattern('^AseLaps-[0-9]+_[0-9]+$')][string]$JobName
)

$ErrorActionPreference = 'Stop'
$job = Join-Path ([IO.Path]::GetTempPath()) $JobName
$request = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $job 'request.json') | ConvertFrom-Json

switch ($Action) {
    'export' {
        $executable = [string]$request.executable
        $ffArgs = [string[]]$request.arguments
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 1
        & $executable @ffArgs 2>&1 | Out-File -Encoding UTF8 -LiteralPath $request.log -ErrorAction Stop
        exit $LASTEXITCODE
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
