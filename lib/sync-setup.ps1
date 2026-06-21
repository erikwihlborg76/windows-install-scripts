function Select-InstallTarget {
    Write-Host ""
    Write-Host "========== Select target =========="
    Write-Host "  [1] HOME"
    Write-Host "  [2] WORK"
    Write-Host ""

    $choice = Read-Choice -Prompt "Enter choice (1-2)" -AllowedValues @("1", "2")

    switch ($choice) {
        "1" { return "HOME" }
        "2" { return "WORK" }
    }
}

function Select-SyncClient {
    Write-Host ""
    Write-Host "========== Select sync client =========="
    Write-Host "  [1] OneDrive Business"
    Write-Host "  [2] OneDrive (regular)"
    Write-Host "  [3] Dropbox"
    Write-Host ""

    $choice = Read-Choice -Prompt "Enter choice (1-3)" -AllowedValues @("1", "2", "3")

    $syncApp = switch ($choice) {
        "1" { "OneDriveBusiness" }
        "2" { "OneDrive" }
        "3" { "Dropbox" }
    }

    return $syncApp
}

function Confirm-Continue {
    param(
        [Parameter(Mandatory)]
        [string] $Target,

        [Parameter(Mandatory)]
        [string] $SyncApp,

        [Parameter(Mandatory)]
        [string] $SyncRoot
    )

    Write-Host ""
    Write-Host "Target selected: $Target"
    Write-Host "Sync app: $SyncApp"
    Write-Host "Sync root: $SyncRoot"
    Write-Host ""

    $answer = Read-Choice `
        -Prompt "Continue? (Y/N)" `
        -AllowedValues @("Y", "y", "N", "n")

    return ($answer -match "^[Yy]$")
}

function Resolve-DropboxRoot {
    $infoPath = Join-Path $env:APPDATA "Dropbox\info.json"

    if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf)) {
        throw "Dropbox account information was not found at: $infoPath. Install Dropbox and sign in before running this installer."
    }

    try {
        $dropboxInfo = Get-Content -LiteralPath $infoPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
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
    param(
        [Parameter(Mandatory)]
        [ValidateSet("OneDriveBusiness", "OneDrive", "Dropbox")]
        [string] $SyncApp
    )

    if ($SyncApp -eq "Dropbox") {
        $syncRoot = Resolve-DropboxRoot
    }
    else {
        $environmentVariable = switch ($SyncApp) {
            "OneDriveBusiness" { "OneDriveCommercial" }
            "OneDrive"         { "OneDriveConsumer" }
        }

        $syncRoot = [Environment]::GetEnvironmentVariable($environmentVariable)

        if ([string]::IsNullOrWhiteSpace($syncRoot)) {
            throw "Environment variable is not set: `$env:$environmentVariable"
        }
    }

    if (-not (Test-Path -LiteralPath $syncRoot -PathType Container)) {
        throw "Resolved $SyncApp sync root does not exist: $syncRoot"
    }

    foreach ($requiredFolder in @("Apps", "Apps-data")) {
        $requiredPath = Join-Path $syncRoot $requiredFolder
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Container)) {
            throw "Required sync folder does not exist: $requiredPath"
        }
    }

    return (Resolve-Path -LiteralPath $syncRoot -ErrorAction Stop).ProviderPath
}
