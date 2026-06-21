# 02-select-sync-root.ps1
# Usage:
#   .\02-select-sync-root.ps1
#
# Selects a target and sync client, then resolves and validates the sync root.

$ErrorActionPreference = "Stop"

$libDir = Join-Path $PSScriptRoot "lib"
. (Join-Path $libDir "input.ps1")
. (Join-Path $libDir "sync-setup.ps1")

$target = Select-InstallTarget
$syncApp = Select-SyncClient
$syncRoot = Resolve-SyncRoot -SyncApp $syncApp

$continue = Confirm-Continue `
    -Target $target `
    -SyncApp $syncApp `
    -SyncRoot $syncRoot

if (-not $continue) {
    Write-Host "Cancelled."
    return
}

return [pscustomobject]@{
    Target   = $target
    SyncApp  = $syncApp
    SyncRoot = $syncRoot
}
