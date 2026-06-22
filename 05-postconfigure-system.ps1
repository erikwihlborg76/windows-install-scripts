# 05-postconfigure-system.ps1
# Usage:
#   .\05-postconfigure-system.ps1 -Target HOME -SyncRoot "<sync-root>"
#   .\05-postconfigure-system.ps1 -Target WORK -SyncRoot "<sync-root>"
#
# Normally invoked by .\01-run-install-steps.ps1.

param(
    [Parameter(Mandatory)]
    [ValidateSet("HOME", "WORK")]
    [string] $Target,

    [Parameter(Mandatory)]
    [string] $SyncRoot
)

$ErrorActionPreference = "Stop"

$ResourcesDir = Join-Path $PSScriptRoot "resources"
$logPath = Join-Path $env:TEMP "05-postconfigure-system.log"

# ============================================================
# Functions
# ============================================================

$LibDir = Join-Path $PSScriptRoot "lib"
. (Join-Path $LibDir "admin.ps1")
. (Join-Path $LibDir "logging.ps1")
. (Join-Path $LibDir "links-and-copy.ps1")
. (Join-Path $LibDir "apply-settings.ps1")
. (Join-Path $PSScriptRoot "settings\windows.ps1")

# ============================================================
# Main
# ============================================================

try {
    Initialize-InstallLog -Path $logPath -StartMessage "Starting post-configure"
    Assert-Administrator

    Write-Host ""
    Write-Host "========== Post-configure =========="
    Write-Host "Target: $Target"
    Write-Host "Log: `"$logPath`""

    Copy-WindowsTerminalSettings -ResourcesDir $ResourcesDir
    Copy-PowerToysSettings -SyncRoot $SyncRoot

    Set-WindowsSettings -Target $Target
    Import-Lgpo -ResourcesDir $ResourcesDir

    # ===== Omnissa Horizon OS Optimization Tool =====
    # Disabled by default.
    #
    # Write-Host ""
    # Write-Host "========== Omnissa Horizon OS Optimization Tool =========="
    # $ohot = Join-Path $ResourcesDir "Windows OS Optimization Tool for Horizon"
    # $ohotExe = Join-Path $ohot "OHOT.EXE"
    # $ohotTemplate = Join-Path $ohot "Template.xml"
    # $ohotLog = Join-Path $env:TEMP "OHOT.log"
    #
    # if ((Test-Path -LiteralPath $ohotExe -PathType Leaf) -and
    #     (Test-Path -LiteralPath $ohotTemplate -PathType Leaf)) {
    #     & $ohotExe -o -t $ohotTemplate -v > $ohotLog 2>&1
    # }
    # else {
    #     Write-Warn "OHOT files missing."
    # }

    Write-Host ""
    Write-Host "========== Wake devices =========="
    Disable-NetworkAdapterWake

    Write-Host ""
    Write-Host "========== Wake timers =========="
    Disable-WakeTimers

    Write-Host ""
    Write-Host "========== Summary =========="

    $warningCount = Get-InstallWarningCount

    if ($warningCount -eq 0) {
        Write-Host "[OK] Post-configure completed without warnings."
        Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Completed without warnings."
        exit 0
    }

    Write-Host "[WARN] Post-configure completed with $warningCount warning(s)."
    Write-Host "Check log:"
    Write-Host "`"$logPath`""
    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Completed with $warningCount warning(s)."

    exit 0
}
catch {
    $message = $_.Exception.Message

    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = ($_ | Out-String).Trim()
    }

    Write-Host ""
    Write-Host "[ERROR] $message"
    try {
        Write-LogLine "[ERROR] $message"
    }
    catch {
        Write-Host "[WARN] Could not write the error to the log."
    }
    exit 1
}
