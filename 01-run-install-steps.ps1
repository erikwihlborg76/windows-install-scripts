# 01-run-install-steps.ps1
# Usage:
#   Launch .\00-run-install-manual.cmd
#
# PowerShell installer orchestrator. The CMD entry point configures script execution first.

$ErrorActionPreference = "Stop"

$installDir = $PSScriptRoot
$libDir = Join-Path $installDir "lib"
$selectSyncRootScript = Join-Path $installDir "02-select-sync-root.ps1"

. (Join-Path $libDir "admin.ps1")
. (Join-Path $libDir "input.ps1")
. (Join-Path $libDir "install-runner.ps1")
. (Join-Path $libDir "winget.ps1")

if (Restart-ScriptAsAdministrator -ScriptPath $PSCommandPath) {
    exit 0
}

try {
    Assert-WinGet

    $resourcesDir = Join-Path $installDir "resources"

    if (-not (Test-Path -LiteralPath $resourcesDir -PathType Container)) {
        throw "Missing resources directory: $resourcesDir"
    }

    $mode = Select-InstallMode

    if ($mode -eq "FULL") {
        if (-not (Test-Path -LiteralPath $selectSyncRootScript -PathType Leaf)) {
            throw "Missing sync root selection script: $selectSyncRootScript"
        }

        $selection = & $selectSyncRootScript

        if (-not $selection) {
            Write-Host "Workflow cancelled."
            exit 0
        }

        $target = $selection.Target
        $syncApp = $selection.SyncApp
        $syncRoot = $selection.SyncRoot

        $steps = @(
            @{
                Name       = "03-preconfigure-system.ps1"
                Parameters = @{ SyncRoot = $syncRoot }
            }
            @{
                Name       = "04-install-apps.ps1"
                Parameters = @{ Target = $target }
            }
            @{
                Name       = "05-postconfigure-system.ps1"
                Parameters = @{ SyncRoot = $syncRoot }
            }
            @{
                Name       = "06-apply-system-tweaks.ps1"
                Parameters = @{ Target = $target }
            }
            @{
                Name       = "07-remove-apps.ps1"
                Parameters = @{ Target = $target }
            }
        )
    }
    else {
        $target = Select-InstallTarget

        if (-not (Confirm-TweaksAndRemoval -Target $target)) {
            Write-Host "Workflow cancelled."
            exit 0
        }

        $steps = @(
            @{
                Name       = "06-apply-system-tweaks.ps1"
                Parameters = @{ Target = $target }
            }
            @{
                Name       = "07-remove-apps.ps1"
                Parameters = @{ Target = $target }
            }
        )
    }

    $workflowName = if ($mode -eq "FULL") {
        "Full install"
    }
    else {
        "Tweaks and app removal only"
    }

    Write-Host ""
    Write-Host "========== Running install steps =========="
    Write-Host "Workflow:    $workflowName"
    Write-Host "Target:      $target"

    if ($mode -eq "FULL") {
        Write-Host "Sync app:    $syncApp"
        Write-Host "Sync root:   $syncRoot"
    }

    Write-Host "Install dir: $installDir"
    Write-Host "Resources:   $resourcesDir"

    foreach ($step in $steps) {
        Invoke-InstallStep `
            -Step $step.Name `
            -ScriptRoot $installDir `
            -Parameters $step.Parameters
    }

    Write-Host ""
    Write-Host "========== Complete =========="

    if ($mode -eq "FULL") {
        Write-Host "Installation complete."
    }
    else {
        Write-Host "Windows tweaks and app removal complete."
    }

    Write-Host "Check optional updates in Windows Update."
    Write-Host "Press Enter to exit."
    [void][System.Console]::ReadLine()
    exit 0
}
catch {
    Write-Host ""
    Write-Host "[ERROR] Workflow stopped because a step failed."

    Write-Host $_.Exception.Message
    Write-Host "Press Enter to exit."
    [void][System.Console]::ReadLine()
    exit 10
}
