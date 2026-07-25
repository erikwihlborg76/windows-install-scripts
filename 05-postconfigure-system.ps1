# 05-postconfigure-system.ps1
# Usage:
#   .\05-postconfigure-system.ps1 -SyncRoot "<sync-root>"
#
# Normally invoked by .\01-run-install-steps.ps1.

param(
    [Parameter(Mandatory)]
    [string] $SyncRoot
)

$ErrorActionPreference = "Stop"

$logPath = Join-Path $env:TEMP "05-postconfigure-system.log"

# ============================================================
# Functions
# ============================================================

$LibDir = Join-Path $PSScriptRoot "lib"
. (Join-Path $LibDir "admin.ps1")
. (Join-Path $LibDir "logging.ps1")
. (Join-Path $LibDir "links-and-copy.ps1")
. (Join-Path $LibDir "apply-settings.ps1")

# ============================================================
# Main
# ============================================================

try {
    Initialize-InstallLog -Path $logPath -StartMessage "Starting synced app settings restore"
    Assert-Administrator

    Write-Host ""
    Write-Host "========== Restore synced app settings =========="
    Write-Host "Sync root: `"$SyncRoot`""
    Write-Host "Log: `"$logPath`""

    Copy-PowerToysSettings -SyncRoot $SyncRoot

    Write-Host ""
    Write-Host "========== Summary =========="

    $warningCount = Get-InstallWarningCount

    if ($warningCount -eq 0) {
        Write-Host "[OK] Synced app settings restored without warnings."
        Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Completed without warnings."
        exit 0
    }

    Write-Host "[WARN] Synced app settings completed with $warningCount warning(s)."
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
