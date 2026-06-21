# 06-remove-bloatware.ps1
# Usage:
#   .\06-remove-bloatware.ps1 -Target HOME
#   .\06-remove-bloatware.ps1 -Target WORK
#
# Normally invoked by .\01-run-install-steps.ps1.

param(
    [Parameter(Mandatory)]
    [ValidateSet("HOME", "WORK")]
    [string] $Target
)

$ErrorActionPreference = "Stop"

$logPath = Join-Path $env:TEMP "06-remove-bloatware.log"

# ============================================================
# Functions
# ============================================================

$LibDir = Join-Path $PSScriptRoot "lib"
. (Join-Path $LibDir "admin.ps1")
. (Join-Path $LibDir "logging.ps1")
. (Join-Path $LibDir "winget.ps1")
. (Join-Path $LibDir "app-removal.ps1")

# ============================================================
# Main
# ============================================================

try {
    Initialize-InstallLog -Path $logPath -StartMessage "Starting uninstall cleanup"
    Assert-Administrator
    Assert-WinGet

    Write-Host ""
    Write-Host "========== Uninstall cleanup =========="
    Write-Host "Target: $Target"
    Write-Host "Log: `"$logPath`""
    Write-Host ""

    # ========================================================
    # Common app removals
    # ========================================================

    Write-Host ""
    Write-Host "========== Removing common apps =========="

    # Prefer AppX package patterns for built-in Store apps.
    # Keep winget names where the package is not clearly removable through AppX.

    $appxRemovals = @(
        @{ PackageName = "*WindowsSoundRecorder*"; PackageLabel = "Windows Sound Recorder" }
        @{ PackageName = "*WindowsAlarms*"; PackageLabel = "Windows Clock" }
        @{ PackageName = "*PowerAutomateDesktop*"; PackageLabel = "Power Automate" }
        @{ PackageName = "*GetHelp*"; PackageLabel = "Get Help" }
        @{ PackageName = "*Copilot*"; PackageLabel = "Copilot" }
        @{ PackageName = "*XboxSpeechToTextOverlay*"; PackageLabel = "Game Speech Window" }
        @{ PackageName = "*YourPhone*"; PackageLabel = "Phone Link" }
        @{ PackageName = "*Xbox.TCUI*"; PackageLabel = "Xbox TCUI" }
        @{ PackageName = "*CrossDevice*"; PackageLabel = "Cross Device Experience Host" }
        @{ PackageName = "*QuickAssist*"; PackageLabel = "Quick Assist" }
        @{ PackageName = "*BingNews*"; PackageLabel = "Microsoft News" }
        @{ PackageName = "*BingSearch*"; PackageLabel = "Microsoft Bing Search" }
        @{ PackageName = "*BingWeather*"; PackageLabel = "MSN Weather" }
        @{ PackageName = "*GamingApp*"; PackageLabel = "Xbox" }
        @{ PackageName = "*Solitaire*"; PackageLabel = "Solitaire & Casual Games" }
        @{ PackageName = "*StickyNotes*"; PackageLabel = "Microsoft Sticky Notes" }
        @{ PackageName = "*Paint*"; PackageLabel = "Paint" }
        @{ PackageName = "*Todos*"; PackageLabel = "Microsoft To Do" }
        @{ PackageName = "*WindowsFeedbackHub*"; PackageLabel = "Feedback Hub" }
        @{ PackageName = "*XboxIdentityProvider*"; PackageLabel = "Xbox Identity Provider" }
        @{ PackageName = "*ZuneMusic*"; PackageLabel = "Windows Media Player" }
        @{ PackageName = "*OutlookForWindows*"; PackageLabel = "Outlook for Windows" }
        @{ PackageName = "*Clipchamp*"; PackageLabel = "Microsoft Clipchamp" }
    )

    $wingetNameRemovals = @(
        "Widgets Platform Runtime"
        "Microsoft Bing"
        "Start Experiences App"
        "Microsoft Edge Game Assist"
        "Microsoft 365 Copilot"
    )

    foreach ($appxRemoval in $appxRemovals) {
        Remove-AppxPackageName @appxRemoval
    }

    foreach ($appName in $wingetNameRemovals) {
        Uninstall-Name -AppName $appName
    }

    # ========================================================
    # Windows capabilities
    # ========================================================

    Write-Host ""
    Write-Host "========== Removing Windows capabilities =========="

    Remove-Capability `
        -CapabilityName "Microsoft.Windows.SnippingTool~~~~0.0.1.0" `
        -CapabilityLabel "Snipping Tool"

    # ========================================================
    # HOME-only removals
    # ========================================================

    if ($Target -eq "HOME") {
        Write-Host ""
        Write-Host "========== Removing HOME-only apps =========="

        Uninstall-Name "Microsoft Teams"
    }
    else {
        Write-Host ""
        Write-Info "Skipping Teams removal for WORK target."
    }

    # ========================================================
    # Summary
    # ========================================================

    Write-Host ""
    Write-Host "========== Summary =========="

    $warningCount = Get-InstallWarningCount

    if ($warningCount -eq 0) {
        Write-Host "[OK] Uninstall cleanup completed without warnings."
        Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Completed without warnings."
        exit 0
    }

    Write-Host "[WARN] Uninstall cleanup completed with $warningCount warning(s)."
    Write-Host "Check log:"
    Write-Host "`"$logPath`""
    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Completed with $warningCount warning(s)."

    exit 0
}
catch {
    $message = $_.Exception.Message
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
