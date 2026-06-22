# 04-install-apps.ps1
# Usage:
#   .\04-install-apps.ps1 -Target HOME
#   .\04-install-apps.ps1 -Target WORK
#
# Normally invoked by .\01-run-install-steps.ps1.

param(
    [Parameter(Mandatory)]
    [ValidateSet("HOME", "WORK")]
    [string] $Target
)

$ErrorActionPreference = "Stop"

$logPath = Join-Path $env:TEMP "04-install-apps_winget.log"

$LibDir = Join-Path $PSScriptRoot "lib"
. (Join-Path $LibDir "logging.ps1")
. (Join-Path $LibDir "winget.ps1")
. (Join-Path $LibDir "activation.ps1")

try {
    Initialize-InstallLog -Path $logPath -StartMessage "Starting installs for $Target"
    Assert-WinGet -Message "winget was not found. Run the bootstrap script first, or install/update App Installer from Microsoft Store."

    Write-Host ""
    Write-Host "========== Installing common apps =========="
    Write-Host "Log: `"$logPath`""
    Write-Host ""

    $commonPackages = @(
        @{ Id = "Microsoft.VisualStudioCode"; Source = "winget"; Name = "Visual Studio Code" }
        @{ Id = "PeterPawlowski.foobar2000"; Source = "winget"; Name = "foobar2000" }
        @{ Id = "Microsoft.PowerToys"; Source = "winget"; Name = "PowerToys" }
        @{ Id = "AgileBits.1Password"; Source = "winget"; Name = "1Password" }
        @{ Id = "Ghisler.TotalCommander"; Source = "winget"; Name = "Total Commander" }
        @{ Id = "Highresolution.X-MouseButtonControl"; Source = "winget"; Name = "X-Mouse Button Control" }
        @{ Id = "dotPDN.PaintDotNet"; Source = "winget"; Name = "Paint.NET" }
        @{ Id = "Microsoft.WindowsTerminal"; Source = "winget"; Name = "Windows Terminal" }
        @{ Id = "Microsoft.PowerShell"; Source = "winget"; Name = "PowerShell 7" }
        @{ Id = "Notion.Notion"; Source = "winget"; Name = "Notion" }
        @{ Id = "Git.Git"; Source = "winget"; Name = "Git" }
        @{ Id = "Microsoft.SecurityComplianceToolkit.LGPO"; Source = "winget"; Name = "LGPO" }
    )

    # Install-Pkg "9NMZLZ57R3T7"                        "msstore" "HEVC Video Extensions" -Optional
    # Install-Pkg "Postman.Postman"                     "winget"  "Postman"
    # Install-Pkg "Stoplight.Studio"                    "winget"  "Stoplight Studio"
    # Install-Pkg "Microsoft.DSC"                       "winget"  "Microsoft DSC"

    foreach ($package in $commonPackages) {
        Install-Pkg @package
    }

    if ($Target -eq "WORK") {
        Write-Host ""
        Write-Host "========== Installing WORK-specific apps =========="
        Install-Pkg "OpenJS.NodeJS.LTS" "winget" "Node.js LTS"
    }
    Write-Host ""
    Write-Host "========== Windows activation check =========="
    Test-WindowsActivation

    Write-Host ""
    Write-Host "========== Summary =========="

    $warningCount = Get-InstallWarningCount

    if ($warningCount -eq 0) {
        Write-Host "[OK] All winget install commands completed successfully."
    }
    else {
        Write-Host "[WARN] $warningCount package install command(s) failed."
        Write-Host "Check the log:"
        Write-Host "`"$logPath`""
    }

    Write-Host ""
    Write-Host "Done."

    if ($warningCount -eq 0) {
        exit 0
    }

    exit 1
}
catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)"
    exit 1
}
