function Resolve-DropboxRoot {
    $infoPath = Join-Path $env:APPDATA "Dropbox\info.json"

    if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf)) {
        throw "Dropbox account information was not found at '$infoPath'. Install Dropbox and sign in before running this installer."
    }

    try {
        $dropboxInfo = Get-Content -LiteralPath $infoPath -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Could not read Dropbox account information from '$infoPath': $($_.Exception.Message)"
    }

    $accounts = @(
        foreach ($property in $dropboxInfo.PSObject.Properties) {
            $accountPath = [string] $property.Value.path
            if (-not [string]::IsNullOrWhiteSpace($accountPath)) {
                [pscustomobject]@{
                    Name = $property.Name
                    Path = $accountPath
                }
            }
        }
    )

    if ($accounts.Count -eq 0) {
        throw "Dropbox account information at '$infoPath' does not contain an account path."
    }

    if ($accounts.Count -eq 1) {
        return $accounts[0].Path
    }

    $matchingAccounts = @(
        $accounts | Where-Object {
            (Test-Path -LiteralPath $_.Path -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $_.Path "Apps") -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $_.Path "Apps-data") -PathType Container)
        }
    )

    if ($matchingAccounts.Count -eq 1) {
        return $matchingAccounts[0].Path
    }

    $accountDetails = ($accounts | ForEach-Object { "$($_.Name): $($_.Path)" }) -join "; "
    if ($matchingAccounts.Count -eq 0) {
        throw "Multiple Dropbox accounts were found, but none contain both required folders 'Apps' and 'Apps-data'. Detected accounts: $accountDetails"
    }

    $matchingDetails = ($matchingAccounts | ForEach-Object { "$($_.Name): $($_.Path)" }) -join "; "
    throw "Multiple Dropbox accounts contain both required folders, so the sync root is ambiguous: $matchingDetails"
}

function Resolve-SyncRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("OneDriveBusiness", "OneDrive", "Dropbox")]
        [string] $SyncProvider,

        [Parameter()]
        [string] $SyncRootOverride
    )

    if (-not [string]::IsNullOrWhiteSpace($SyncRootOverride)) {
        $resolvedRoot = $SyncRootOverride
    }
    elseif ($SyncProvider -eq "Dropbox") {
        $resolvedRoot = Resolve-DropboxRoot
    }
    else {
        $environmentVariable = switch ($SyncProvider) {
            "OneDriveBusiness" { "OneDriveCommercial" }
            "OneDrive" { "OneDriveConsumer" }
        }

        $resolvedRoot = [Environment]::GetEnvironmentVariable($environmentVariable)
        if ([string]::IsNullOrWhiteSpace($resolvedRoot)) {
            throw "Environment variable is not set: `$env:$environmentVariable"
        }
    }

    if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
        throw "Resolved $SyncProvider sync root does not exist: $resolvedRoot"
    }

    foreach ($requiredFolder in @("Apps", "Apps-data")) {
        $requiredPath = Join-Path $resolvedRoot $requiredFolder
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Container)) {
            throw "Required sync folder does not exist: $requiredPath"
        }
    }

    return (Resolve-Path -LiteralPath $resolvedRoot -ErrorAction Stop).ProviderPath
}

function Test-ReparsePoint {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    return [bool] ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Get-ReparsePointTarget {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $target = @($item.Target) | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($target)) {
        $target = @($item.LinkTarget) | Select-Object -First 1
    }

    return $target
}

function Test-SamePath {
    param(
        [Parameter(Mandatory)]
        [string] $FirstPath,

        [Parameter(Mandatory)]
        [string] $SecondPath
    )

    $firstFullPath = [IO.Path]::GetFullPath($FirstPath).TrimEnd('\')
    $secondFullPath = [IO.Path]::GetFullPath($SecondPath).TrimEnd('\')
    return [string]::Equals(
        $firstFullPath,
        $secondFullPath,
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Remove-ReparsePoint {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer) {
        [IO.Directory]::Delete($item.FullName)
    }
    else {
        [IO.File]::Delete($item.FullName)
    }
}

function Set-ProfileLink {
    param(
        [Parameter(Mandatory)]
        [string] $LinkPath,

        [Parameter(Mandatory)]
        [string] $TargetPath,

        [Parameter()]
        [switch] $Required
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        if ($Required) {
            throw "Required link target does not exist: '$TargetPath'"
        }
        Write-Warning "Optional link target is missing; skipping '$LinkPath' -> '$TargetPath'."
        return
    }

    $parent = Split-Path -Parent $LinkPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    }

    if (Test-Path -LiteralPath $LinkPath) {
        if (-not (Test-ReparsePoint -Path $LinkPath)) {
            if ($Required) {
                throw "Required link path already exists and is not a link: '$LinkPath'. Move or rename it, then run the installer again."
            }
            Write-Warning "Link path already exists and is not a link; skipping '$LinkPath'."
            return
        }

        $existingTarget = Get-ReparsePointTarget -Path $LinkPath
        if ($existingTarget -and (Test-SamePath -FirstPath $existingTarget -SecondPath $TargetPath)) {
            Write-Host "[OK] Link already points to the requested target: '$LinkPath' -> '$TargetPath'"
            return
        }

        Remove-ReparsePoint -Path $LinkPath
    }

    try {
        $targetItem = Get-Item -LiteralPath $TargetPath -Force -ErrorAction Stop
        $itemType = if ($targetItem.PSIsContainer) { "Junction" } else { "SymbolicLink" }

        New-Item `
            -ItemType $itemType `
            -Path $LinkPath `
            -Target $TargetPath `
            -Force `
            -ErrorAction Stop |
            Out-Null

        Write-Host "[OK] Linked '$LinkPath' -> '$TargetPath'"
    }
    catch {
        if ($Required) {
            throw "Failed to create required link '$LinkPath' -> '$TargetPath': $($_.Exception.Message)"
        }
        Write-Warning "Failed to create optional link '$LinkPath' -> '$TargetPath': $($_.Exception.Message)"
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory)]
        [string] $Source,

        [Parameter(Mandatory)]
        [string] $Destination,

        [Parameter(Mandatory)]
        [string] $Description
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-Host "[SKIP] $Description source not found: $Source"
        return
    }

    New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null

    & robocopy.exe $Source $Destination /E /NFL /NDL /NJH /NJS /NP | Out-Null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ge 8) {
        Write-Warning "$Description copy failed with Robocopy exit code ${exitCode}: '$Source' -> '$Destination'"
        return
    }

    Write-Host "[OK] Copied $Description."
}

function Initialize-SyncedProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SyncRoot
    )

    if (-not (Test-Path -LiteralPath $SyncRoot -PathType Container)) {
        throw "Sync root does not exist: $SyncRoot"
    }

    Write-Host ""
    Write-Host "========== Preparing sync-backed profile =========="
    Write-Host "Sync root: $SyncRoot"

    $links = @(
        @{ LinkPath = "C:\Apps"; TargetPath = (Join-Path $SyncRoot "Apps"); Required = $true }
        @{ LinkPath = "C:\Apps-data"; TargetPath = (Join-Path $SyncRoot "Apps-data"); Required = $true }
        @{ LinkPath = (Join-Path $env:USERPROFILE ".openhue"); TargetPath = (Join-Path $SyncRoot "Apps-data\.openhue") }
        @{ LinkPath = (Join-Path $env:APPDATA "GHISLER"); TargetPath = (Join-Path $SyncRoot "Apps-data\GHISLER") }
        @{ LinkPath = (Join-Path $env:APPDATA "Highresolution Enterprises"); TargetPath = (Join-Path $SyncRoot "Apps-data\Highresolution Enterprises") }
    )

    foreach ($link in $links) {
        Set-ProfileLink @link
    }

    $foobarSource = Join-Path $SyncRoot "Apps-data\foobar2000-v2"
    $foobarDestination = Join-Path $env:APPDATA "foobar2000-v2"
    New-Item -ItemType Directory -Path $foobarDestination -Force -ErrorAction Stop | Out-Null

    $foobarConfig = Join-Path $foobarSource "config.sqlite"
    if (Test-Path -LiteralPath $foobarConfig -PathType Leaf) {
        Copy-Item `
            -LiteralPath $foobarConfig `
            -Destination $foobarDestination `
            -Force `
            -ErrorAction Stop
        Write-Host "[OK] Copied foobar2000 configuration."
    }
    else {
        Write-Warning "foobar2000 configuration was not found: $foobarConfig"
    }

    Set-ProfileLink `
        -LinkPath (Join-Path $foobarDestination "playlists-v2.0") `
        -TargetPath (Join-Path $foobarSource "playlists-v2.0")

    $startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    Copy-DirectoryContents `
        -Source (Join-Path $SyncRoot "Apps-data\Shortcuts") `
        -Destination $startMenu `
        -Description "Start-menu shortcuts"
}

function Restore-SyncedApplicationState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SyncRoot
    )

    Write-Host ""
    Write-Host "========== Restoring sync-backed application state =========="

    $powerToysRoot = Join-Path $SyncRoot "Apps-data\PowerToys"
    if (-not (Test-Path -LiteralPath $powerToysRoot -PathType Container)) {
        Write-Host "[SKIP] PowerToys state was not found: $powerToysRoot"
        return
    }

    Copy-DirectoryContents `
        -Source (Join-Path $powerToysRoot "FancyZones") `
        -Destination (Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones") `
        -Description "PowerToys FancyZones state"

    Copy-DirectoryContents `
        -Source (Join-Path $powerToysRoot "LightSwitch") `
        -Destination (Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\LightSwitch") `
        -Description "PowerToys LightSwitch state"

    $commandPaletteSettings = Join-Path $powerToysRoot "CommandPalette\settings.json"
    if (-not (Test-Path -LiteralPath $commandPaletteSettings -PathType Leaf)) {
        Write-Host "[SKIP] Command Palette settings were not found: $commandPaletteSettings"
        return
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA "Packages"
    $commandPalettePackages = @(
        Get-ChildItem `
            -LiteralPath $packagesRoot `
            -Directory `
            -Filter "Microsoft.CommandPalette_*" `
            -ErrorAction SilentlyContinue
    )

    if ($commandPalettePackages.Count -eq 0) {
        Write-Warning "No Microsoft Command Palette package folder was found."
        return
    }

    foreach ($package in $commandPalettePackages) {
        $localState = Join-Path $package.FullName "LocalState"
        $destination = Join-Path $localState "settings.json"

        try {
            New-Item -ItemType Directory -Path $localState -Force -ErrorAction Stop | Out-Null
            Copy-Item `
                -LiteralPath $commandPaletteSettings `
                -Destination $destination `
                -Force `
                -ErrorAction Stop
            Write-Host "[OK] Copied Command Palette settings to $destination"
        }
        catch {
            Write-Warning "Failed to copy Command Palette settings to '$destination': $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function @(
    "Initialize-SyncedProfile"
    "Resolve-SyncRoot"
    "Restore-SyncedApplicationState"
)
