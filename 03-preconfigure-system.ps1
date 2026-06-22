# 03-preconfigure-system.ps1
# Usage:
#   .\03-preconfigure-system.ps1 -Target HOME -SyncRoot "<sync-root>"
#   .\03-preconfigure-system.ps1 -Target WORK -SyncRoot "<sync-root>"
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

# ============================================================
# Functions
# ============================================================

$LibDir = Join-Path $PSScriptRoot "lib"
. (Join-Path $LibDir "admin.ps1")
. (Join-Path $LibDir "links-and-copy.ps1")
. (Join-Path $LibDir "system-info.ps1")

# ============================================================
# Main
# ============================================================

try {
    Assert-Administrator

    $StartMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"

    if (-not (Test-Path -LiteralPath $SyncRoot -PathType Container)) {
        throw "SyncRoot does not exist: $SyncRoot"
    }

    switch ($Target) {
        "HOME" {
            $BootMenuEntry = "Home"
        }
        "WORK" {
            $BootMenuEntry = "Work"
        }
    }

    Write-Host ""
    Write-Host "Using target: $Target"
    Write-Host "Using SyncRoot: `"$SyncRoot`""

    # ========================================================
    # Boot menu entry
    # ========================================================

    Write-Host ""
    $windowsName = Get-WindowsDisplayName
    $BootMenuDescription = "$windowsName $BootMenuEntry"

    Write-Host ""
    Write-Host "Detected operating system: $windowsName"
    Write-Host "Setting boot menu entry to: `"$BootMenuDescription`""

    & bcdedit.exe /set "{current}" description "$BootMenuDescription"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] Failed to update boot entry description with BCDEdit."
    }
    else {
        Write-Host "[OK] Updated boot entry description."
    }

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
    # HOME-specific setup
    # ========================================================

    if ($Target -eq "HOME") {
        Write-Host ""
        Write-Host "========== HOME setup =========="

        Write-Host ""
        Write-Host "Type the new computer name, or leave empty to skip."
        Write-Host "Example: GIGABYTE-Z690"

        $NewComputerName = Read-Host ">"

        if (-not [string]::IsNullOrWhiteSpace($NewComputerName)) {
            Write-Host "Renaming computer to `"$NewComputerName`"..."

            try {
                Rename-Computer -NewName $NewComputerName -Force -ErrorAction Stop
                Write-Host "[OK] Computer rename requested."
                Write-Host "NOTE: A reboot is required for the new name to take effect."
            }
            catch {
                Write-Host "[WARN] Failed to rename computer."
                Write-Host $_.Exception.Message
            }
        }
        else {
            Write-Host "[INFO] Computer rename skipped."
        }
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
