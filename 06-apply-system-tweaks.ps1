# 06-apply-system-tweaks.ps1
# Usage:
#   .\06-apply-system-tweaks.ps1 -Target HOME
#   .\06-apply-system-tweaks.ps1 -Target WORK
#
# This step does not read from the configured sync root or C:\Apps(-data).
# Normally invoked by .\01-run-install-steps.ps1.

param(
    [Parameter(Mandatory)]
    [ValidateSet("HOME", "WORK")]
    [string] $Target
)

$ErrorActionPreference = "Stop"

$ResourcesDir = Join-Path $PSScriptRoot "resources"
$logPath = Join-Path $env:TEMP "06-apply-system-tweaks.log"

# ============================================================
# Functions
# ============================================================

$LibDir = Join-Path $PSScriptRoot "lib"
. (Join-Path $LibDir "admin.ps1")
. (Join-Path $LibDir "logging.ps1")
. (Join-Path $LibDir "winget.ps1")
. (Join-Path $LibDir "system-info.ps1")
. (Join-Path $LibDir "apply-settings.ps1")
. (Join-Path $PSScriptRoot "settings\windows.ps1")

# ============================================================
# Main
# ============================================================

try {
    Initialize-InstallLog -Path $logPath -StartMessage "Starting sync-root-independent system tweaks"
    Assert-Administrator

    Write-Host ""
    Write-Host "========== Apply system tweaks =========="
    Write-Host "Target: $Target"
    Write-Host "Log: `"$logPath`""

    # ========================================================
    # Boot menu entry
    # ========================================================

    $bootMenuEntry = switch ($Target) {
        "HOME" { "Home" }
        "WORK" { "Work" }
    }

    Write-Host ""
    $windowsName = Get-WindowsDisplayName
    $bootMenuDescription = "$windowsName $bootMenuEntry"

    Write-Host "Detected operating system: $windowsName"
    Write-Host "Setting boot menu entry to: `"$bootMenuDescription`""

    & bcdedit.exe /set "{current}" description "$bootMenuDescription"

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Failed to update boot entry description with BCDEdit."
    }
    else {
        Write-Ok "Updated boot entry description."
    }

    # ========================================================
    # HOME-specific setup
    # ========================================================

    if ($Target -eq "HOME") {
        Write-Host ""
        Write-Host "========== HOME setup =========="
        Write-Host ""
        Write-Host "Type the new computer name, or leave empty to skip."
        Write-Host "Example: GIGABYTE-Z690"

        $newComputerName = Read-Host ">"

        if (-not [string]::IsNullOrWhiteSpace($newComputerName)) {
            Write-Host "Renaming computer to `"$newComputerName`"..."

            try {
                Rename-Computer -NewName $newComputerName -Force -ErrorAction Stop
                Write-Ok "Computer rename requested."
                Write-Host "NOTE: A reboot is required for the new name to take effect."
            }
            catch {
                Write-Warn "Failed to rename computer. $($_.Exception.Message)"
            }
        }
        else {
            Write-Info "Computer rename skipped."
        }
    }

    Set-WindowsSettings -Target $Target
    Import-Lgpo -ResourcesDir $ResourcesDir

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
        Write-Host "[OK] System tweaks completed without warnings."
        Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Completed without warnings."
        exit 0
    }

    Write-Host "[WARN] System tweaks completed with $warningCount warning(s)."
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
