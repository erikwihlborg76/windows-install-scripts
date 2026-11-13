function Resolve-DropboxRoot {
    $infoPaths = @(
        Join-Path $env:APPDATA "Dropbox\info.json"
        Join-Path $env:LOCALAPPDATA "Dropbox\info.json"
    )
    $infoPath = $infoPaths | Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    } | Select-Object -First 1

    if (-not $infoPath) {
        throw "Dropbox account information was not found at either '$($infoPaths -join "' or '")'. Install Dropbox and sign in before running this installer."
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
        Write-Host "[SKIP] Optional link target is missing: '$LinkPath' -> '$TargetPath'."
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

    # Robocopy uses nonzero success codes and otherwise retries for days by default.
    # Keep its output in the transcript so failed copies remain diagnosable.
    $PSNativeCommandUseErrorActionPreference = $false
    & robocopy.exe $Source $Destination /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Host
    $exitCode = $LASTEXITCODE
    if ($exitCode -ge 8) {
        Write-Warning "$Description copy failed with Robocopy exit code ${exitCode}: '$Source' -> '$Destination'"
        return
    }

    Write-Host "[OK] Copied $Description."
}

function Set-SshIncludeConfiguration {
    param(
        [Parameter(Mandatory)]
        [string] $UserProfile
    )

    $sshDirectory = Join-Path $UserProfile ".ssh"
    $sshConfig = Join-Path $sshDirectory "config"
    $includeDirective = "Include c:/Apps-data/SSH/config"

    New-Item `
        -ItemType Directory `
        -Path $sshDirectory `
        -Force `
        -ErrorAction Stop |
        Out-Null

    $content = if (Test-Path -LiteralPath $sshConfig -PathType Leaf) {
        [IO.File]::ReadAllText($sshConfig)
    }
    else {
        ""
    }

    $includePattern = '(?im)^[\t ]*Include[\t ]+c:/Apps-data/SSH/config[\t ]*(?:#[^\r\n]*)?\r?(?:\n|$)'
    $includes = [regex]::Matches($content, $includePattern)
    if ($includes.Count -eq 1) {
        $precedingContent = $content.Substring(0, $includes[0].Index)
        $scopes = [regex]::Matches($precedingContent, '(?im)^[\t ]*(?:Host|Match)[\t ]+[^\r\n]*')
        if ($scopes.Count -eq 0 -or $scopes[$scopes.Count - 1].Value -match '(?i)^[\t ]*Host[\t ]+\*[\t ]*(?:#.*)?$') {
            Write-Host "[OK] SSH configuration already includes '$includeDirective' for all hosts."
            return
        }
    }

    # Repair older conditional includes and keep local settings first: OpenSSH
    # uses the first value it finds. A new Host block also ends any prior Match.
    $content = [regex]::Replace($content, $includePattern, "")
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { [Environment]::NewLine }
    if ($content.Length -gt 0) {
        if (-not $content.EndsWith("`n")) {
            $content += $newline
        }
        $content += "Host *$newline"
    }
    $content += "$includeDirective$newline"

    [IO.File]::WriteAllText($sshConfig, $content, [Text.UTF8Encoding]::new($false))
    Write-Host "[OK] Configured the synced SSH include in '$sshConfig'."
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
    )

    foreach ($link in $links) {
        Set-ProfileLink @link
    }

    Set-SshIncludeConfiguration -UserProfile $env:USERPROFILE

    $startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    Copy-DirectoryContents `
        -Source (Join-Path $SyncRoot "Apps-data\Shortcuts") `
        -Destination $startMenu `
        -Description "Start-menu shortcuts"
}

Export-ModuleMember -Function @(
    "Initialize-SyncedProfile"
    "Resolve-SyncRoot"
)
