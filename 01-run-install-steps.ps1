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
. (Join-Path $libDir "install-runner.ps1")

if (Restart-ScriptAsAdministrator -ScriptPath $PSCommandPath) {
    exit 0
}

try {
    if (-not (Test-Path -LiteralPath $selectSyncRootScript -PathType Leaf)) {
        throw "Missing sync root selection script: $selectSyncRootScript"
    }

    $selection = & $selectSyncRootScript

    if (-not $selection) {
        Write-Host "Installation cancelled."
        exit 0
    }

    $target = $selection.Target
    $syncApp = $selection.SyncApp
    $syncRoot = $selection.SyncRoot
    $resourcesDir = Join-Path $installDir "resources"

    if (-not (Test-Path -LiteralPath $resourcesDir -PathType Container)) {
        throw "Missing resources directory: $resourcesDir"
    }

    Write-Host ""
    Write-Host "========== Running install steps =========="
    Write-Host "Target:      $target"
    Write-Host "Sync app:    $syncApp"
    Write-Host "Sync root:   $syncRoot"
    Write-Host "Install dir: $installDir"
    Write-Host "Resources:   $resourcesDir"

    $steps = @(
        @{
            Name       = "03-preconfigure-system.ps1"
            Parameters = @{ Target = $target; SyncRoot = $syncRoot }
        }
        @{
            Name       = "04-install-apps.ps1"
            Parameters = @{ Target = $target }
        }
        @{
            Name       = "05-postconfigure-system.ps1"
            Parameters = @{ Target = $target; SyncRoot = $syncRoot }
        }
        @{
            Name       = "06-remove-apps.ps1"
            Parameters = @{ Target = $target }
        }
    )

    foreach ($step in $steps) {
        Invoke-InstallStep `
            -Step $step.Name `
            -ScriptRoot $installDir `
            -Parameters $step.Parameters
    }

    Write-Host ""
    Write-Host "========== Complete =========="
    Write-Host "Installation complete."
    Write-Host "Check optional updates in Windows Update."
    Write-Host "Press Enter to exit."
    [void][System.Console]::ReadLine()
    exit 0
}
catch {
    Write-Host ""
    Write-Host "[ERROR] Installation stopped because a step failed."

    Write-Host $_.Exception.Message
    Write-Host "Press Enter to exit."
    [void][System.Console]::ReadLine()
    exit 10
}
