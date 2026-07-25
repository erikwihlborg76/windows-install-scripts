# 03-preconfigure-system.ps1
# Usage:
#   .\03-preconfigure-system.ps1 -SyncRoot "<sync-root>"
#
# Normally invoked by .\01-run-install-steps.ps1.

param(
    [Parameter(Mandatory)]
    [string] $SyncRoot
)

$ErrorActionPreference = "Stop"

# ============================================================
# Functions
# ============================================================

$LibDir = Join-Path $PSScriptRoot "lib"
. (Join-Path $LibDir "admin.ps1")
. (Join-Path $LibDir "links-and-copy.ps1")

# ============================================================
# Main
# ============================================================

try {
    Assert-Administrator

    $StartMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"

    if (-not (Test-Path -LiteralPath $SyncRoot -PathType Container)) {
        throw "SyncRoot does not exist: $SyncRoot"
    }

    Write-Host ""
    Write-Host "Using SyncRoot: `"$SyncRoot`""

    # ========================================================
    # Links
    # ========================================================

    Write-Host ""
    Write-Host "========== Creating links =========="

    $links = @(
        @{ LinkPath = "C:\Apps"; TargetPath = (Join-Path $SyncRoot "Apps"); Required = $true }
        @{ LinkPath = "C:\Apps-data"; TargetPath = (Join-Path $SyncRoot "Apps-data"); Required = $true }
        @{ LinkPath = (Join-Path $env:USERPROFILE ".openhue"); TargetPath = (Join-Path $SyncRoot "Apps-data\.openhue") }
        @{ LinkPath = (Join-Path $env:APPDATA "GHISLER"); TargetPath = (Join-Path $SyncRoot "Apps-data\GHISLER") }
        @{ LinkPath = (Join-Path $env:APPDATA "Highresolution Enterprises"); TargetPath = (Join-Path $SyncRoot "Apps-data\Highresolution Enterprises") }
    )

    foreach ($link in $links) {
        Set-FileSystemLink @link
    }

    # ========================================================
    # foobar2000 v2 config
    # ========================================================

    Write-Host ""
    Write-Host "========== foobar2000 setup =========="

    $FoobarAppData = Join-Path $env:APPDATA "foobar2000-v2"
    New-Item -ItemType Directory -Path $FoobarAppData -Force | Out-Null

    Copy-FileIfExists `
        -SourcePath (Join-Path $SyncRoot "Apps-data\foobar2000-v2\config.sqlite") `
        -DestinationFolder $FoobarAppData `
        -Description "foobar2000 config.sqlite"

    Set-FileSystemLink `
        -LinkPath (Join-Path $FoobarAppData "playlists-v2.0") `
        -TargetPath (Join-Path $SyncRoot "Apps-data\foobar2000-v2\playlists-v2.0")

    # ========================================================
    # Start menu shortcuts
    # ========================================================

    Write-Host ""
    Write-Host "========== Start menu shortcuts =========="

    Invoke-RoboCopySafe `
        -SourceFolder "C:\Apps-data\Shortcuts" `
        -DestinationFolder $StartMenu

    Write-Host ""
    Write-Host "Done."
    Write-Host "Some changes may require signing out or rebooting."

    exit 0
}
catch {
    Write-Host ""
    Write-Host "[ERROR] $($_.Exception.Message)"
    exit 1
}
