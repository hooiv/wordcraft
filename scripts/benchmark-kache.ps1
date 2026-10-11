[CmdletBinding()]
param(
    [ValidateSet('Baseline', 'Kache')]
    [string] $Mode = 'Kache',

    [ValidateSet('Check', 'Ci')]
    [string] $Workload = 'Ci',

    [int] $Repeat = 1
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Checked {
    param(
        [Parameter(Mandatory)] [string] $File,
        [Parameter(Mandatory)] [string[]] $Arguments
    )

    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed (exit $LASTEXITCODE): $File $($Arguments -join ' ')"
    }
}

if ($Repeat -lt 1 -or $Repeat -gt 10) {
    throw '-Repeat must be between 1 and 10.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    $kache = Get-Command kache -ErrorAction SilentlyContinue
    if ($Mode -eq 'Kache' -and -not $kache) {
        throw "Kache is not installed. See https://github.com/kunobi-ninja/kache for installation instructions."
    }

    Write-Host "Repository: $repoRoot"
    Write-Host "Revision:   $(git rev-parse HEAD)"
    Write-Host "Mode:       $Mode"
    Write-Host "Workload:   $Workload"
    Write-Host "Repeat:     $Repeat"
    rustc --version
    cargo --version

    $previousWrapper = $env:RUSTC_WRAPPER
    $previousDisabled = $env:KACHE_DISABLED
    if ($Mode -eq 'Kache') {
        # The binary's resolved path is stable even when callers enter through a shim.
        $env:RUSTC_WRAPPER = (Resolve-Path $kache.Source).Path
        Remove-Item Env:KACHE_DISABLED -ErrorAction SilentlyContinue
        Invoke-Checked -File $kache.Source -Arguments @('--version')
        Invoke-Checked -File $kache.Source -Arguments @('doctor')
    } else {
        # Baseline bypasses Kache even if the user's Cargo config enables it.
        $env:KACHE_DISABLED = '1'
    }

    $results = [System.Collections.Generic.List[object]]::new()
    for ($iteration = 1; $iteration -le $Repeat; $iteration++) {
        Write-Host "`n=== $Mode run $iteration/$Repeat ($Workload) ==="
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        if ($Workload -eq 'Ci') {
            Invoke-Checked -File 'cargo' -Arguments @('xtask', 'ci')
        } else {
            Invoke-Checked -File 'cargo' -Arguments @('check', '--workspace', '--locked')
        }
        $timer.Stop()

        $results.Add([pscustomobject]@{
            Mode = $Mode
            Workload = $Workload
            Iteration = $iteration
            Seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 2)
            Revision = (git rev-parse HEAD).Trim()
            Timestamp = (Get-Date).ToString('o')
        })

        if ($Mode -eq 'Kache') {
            Write-Host "`n--- Kache stats for run $iteration ---"
            & $kache.Source stats --last-build
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "kache stats returned exit code $LASTEXITCODE; build succeeded, but capture cache diagnostics manually."
            }
        }
    }

    $reportDir = Join-Path $repoRoot 'target/benchmark-kache'
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    $reportPath = Join-Path $reportDir ("{0}-{1}-{2}.json" -f $Mode.ToLowerInvariant(), $Workload.ToLowerInvariant(), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $results | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $reportPath -Encoding utf8
    Write-Host "`nTiming report: $reportPath"
} finally {
    $env:RUSTC_WRAPPER = $previousWrapper
    if ($null -eq $previousDisabled) {
        Remove-Item Env:KACHE_DISABLED -ErrorAction SilentlyContinue
    } else {
        $env:KACHE_DISABLED = $previousDisabled
    }
    Pop-Location
}
