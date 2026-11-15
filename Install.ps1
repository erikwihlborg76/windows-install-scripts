[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("OneDriveBusiness", "OneDrive", "Dropbox")]
    [string] $SyncProvider,

    [Parameter()]
    [string] $SyncRoot,

    [Parameter()]
    [switch] $SkipConfirmation,

    [Parameter()]
    [switch] $NoPause
)

$ErrorActionPreference = "Stop"

$systemModule = Join-Path $PSScriptRoot "modules\SystemSetup\SystemSetup.psd1"
$syncModule = Join-Path $PSScriptRoot "modules\SyncProfile\SyncProfile.psd1"
$profileDataPath = Join-Path $PSScriptRoot "config\Profiles.psd1"
$configRoot = Join-Path $PSScriptRoot "config"
$resourcesRoot = Join-Path $PSScriptRoot "resources"

Import-Module $systemModule -Force -ErrorAction Stop
Import-Module $syncModule -Force -ErrorAction Stop

function Read-SetupChoice {
    param(
        [Parameter(Mandatory)]
        [string] $Caption,

        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory)]
        [string[]] $Labels,

        [Parameter()]
        [string[]] $Descriptions = @(),

        [Parameter()]
        [int] $DefaultChoice = 0
    )

    $choices = @(
        foreach ($label in $Labels) {
            $marker = $label.IndexOf("&")
            [pscustomobject] @{
                Key = $label.Substring($marker + 1, 1).ToUpperInvariant()
                Label = $label.Replace("&", "")
            }
        }
    )

    Write-Host ""
    Write-Host $Caption -ForegroundColor Cyan
    Write-Host $Message
    Write-Host ""
    for ($index = 0; $index -lt $choices.Count; $index++) {
        Write-Host ("  [{0}] {1}" -f $choices[$index].Key, $choices[$index].Label)
        if ($index -lt $Descriptions.Count -and $Descriptions[$index]) {
            Write-Host "      $($Descriptions[$index])"
        }
        Write-Host ""
    }

    $prompt = "Choose " + ($choices.Key -join "/")
    if ($DefaultChoice -ge 0) {
        $prompt += " (Enter for $($choices[$DefaultChoice].Key))"
    }
    while ($true) {
        $answer = Read-Host $prompt
        if ($null -eq $answer) {
            throw "No selection received. Run the installer in an interactive PowerShell window."
        }
        if ([string]::IsNullOrWhiteSpace($answer) -and $DefaultChoice -ge 0) {
            return $DefaultChoice
        }
        for ($index = 0; $index -lt $choices.Count; $index++) {
            if ($answer.Trim() -eq $choices[$index].Key -or $answer.Trim() -eq $choices[$index].Label) {
                return $index
            }
        }
        Write-Host "Enter one of the letters shown above." -ForegroundColor Yellow
    }
}

try {
    Assert-Windows11

    $elevatedExitCode = Restart-SetupAsAdministrator `
        -ScriptPath $PSCommandPath `
        -BoundParameters $PSBoundParameters

    if ($null -ne $elevatedExitCode) {
        exit $elevatedExitCode
    }

    Assert-WinGet

    if (-not (Test-Path -LiteralPath $profileDataPath -PathType Leaf)) {
        throw "Profile configuration was not found: $profileDataPath"
    }
    if (-not (Test-Path -LiteralPath $resourcesRoot -PathType Container)) {
        throw "Resources directory was not found: $resourcesRoot"
    }

    $configuration = Import-PowerShellDataFile -LiteralPath $profileDataPath

    $modeChoice = Read-SetupChoice `
        -Caption "Set up this PC" `
        -Message "Choose what to include." `
        -Labels @(
            "Configure Windows + &apps"
            "Configure Windows &only"
            "&Full personal setup"
        ) `
        -Descriptions @(
            "Windows settings, selected app removal, and the app bundle."
            "Windows settings and selected app removal."
            "Configuration, apps, and the author's private sync files."
        ) `
        -DefaultChoice -1

    $Mode = @("CONFIGURE_AND_INSTALL", "CONFIGURE_ONLY", "FULL")[$modeChoice]

    $profileChoice = Read-SetupChoice `
        -Caption "PC profile" `
        -Message "What will you use this PC for?" `
        -Labels @("&Home", "&Work") `
        -Descriptions @(
            "Personal PC settings, with an option to rename this PC."
            "Work PC settings with Plan, Work, Meet, and Play desktops."
        ) `
        -DefaultChoice -1

    $Profile = @("HOME", "WORK")[$profileChoice]

    $commonConfiguration = $configuration.Common
    $profileConfiguration = $configuration[$Profile]
    if (-not $commonConfiguration -or -not $profileConfiguration) {
        throw "Profile configuration is incomplete for: $Profile"
    }

    $installApps = $Mode -in @("CONFIGURE_AND_INSTALL", "FULL")
    $useSyncProfile = $Mode -eq "FULL"
    $resolvedSyncRoot = $null

    if ($useSyncProfile) {
        if ([string]::IsNullOrWhiteSpace($SyncProvider)) {
            $providerChoice = Read-SetupChoice `
                -Caption "Personal files" `
                -Message "Where are your Apps and Apps-data folders?" `
                -Labels @("OneDrive &Business", "&OneDrive", "&Dropbox") `
                -Descriptions @(
                    "Your organization's OneDrive folder."
                    "Your personal OneDrive folder."
                    "Your Dropbox folder."
                )

            $SyncProvider = @("OneDriveBusiness", "OneDrive", "Dropbox")[$providerChoice]
        }

        $resolvedSyncRoot = Resolve-SyncRoot `
            -SyncProvider $SyncProvider `
            -SyncRootOverride $SyncRoot
    }

    Write-Host ""
    Write-Host "========== Setup plan =========="
    Write-Host "Mode:         $Mode"
    Write-Host "Profile:      $Profile"
    Write-Host "Install apps: $installApps"
    Write-Host "Use sync:     $useSyncProfile"
    if ($useSyncProfile) {
        Write-Host "Sync provider: $SyncProvider"
        Write-Host "Sync root:     $resolvedSyncRoot"
    }

    if (-not $SkipConfirmation) {
        $confirmation = Read-SetupChoice `
            -Caption "Ready to start?" `
            -Message "Apply the setup plan shown above?" `
            -Labels @("&Yes", "&No")

        if ($confirmation -ne 0) {
            Write-Host "Setup cancelled."
            exit 0
        }
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $transcriptPath = Join-Path $env:TEMP "windows-install-$timestamp.log"
    $transcriptStarted = $false
    $setupWarnings = @()
    $setupExitCode = 0

    try {
        Start-Transcript -Path $transcriptPath -Force -ErrorAction Stop | Out-Null
        $transcriptStarted = $true

        Write-Host ""
        Write-Host "Log: $transcriptPath"

        if ($useSyncProfile) {
            Initialize-SyncedProfile -SyncRoot $resolvedSyncRoot -WarningVariable +setupWarnings
        }

        if ($installApps) {
            Install-Applications `
                -ConfigRoot $configRoot `
                -CommonConfiguration $commonConfiguration `
                -ProfileConfiguration $profileConfiguration `
                -WarningVariable +setupWarnings

            Set-RepositoryApplicationDefaults -ResourcesRoot $resourcesRoot -WarningVariable +setupWarnings
        }

        Invoke-SystemConfiguration `
            -Profile $Profile `
            -CommonConfiguration $commonConfiguration `
            -ProfileConfiguration $profileConfiguration `
            -ResourcesRoot $resourcesRoot `
            -WarningVariable +setupWarnings

        if ($installApps) {
            Set-RepositoryFancyZonesLayout -ResourcesRoot $resourcesRoot -WarningVariable +setupWarnings
        }

        Remove-UnwantedSoftware `
            -CommonConfiguration $commonConfiguration `
            -ProfileConfiguration $profileConfiguration `
            -WarningVariable +setupWarnings

        Write-Host ""
        if ($setupWarnings.Count -gt 0) {
            $setupExitCode = 2
            Write-Host "========== Partially complete =========="
            Write-Host "[WARNING] Setup finished with $($setupWarnings.Count) warning(s):"
            foreach ($setupWarning in $setupWarnings) {
                Write-Host " - $setupWarning"
            }
        }
        else {
            Write-Host "========== Complete =========="
            Write-Host "[OK] Setup completed."
        }
        Write-Host "Log: $transcriptPath"
        Write-Host "Check optional updates in Windows Update."
    }
    catch {
        # Record the failure before finally closes the transcript.
        Write-Host "[ERROR] $($_.Exception.Message)"
        throw
    }
    finally {
        if ($transcriptStarted) {
            try {
                Stop-Transcript | Out-Null
            }
            catch {
                Write-Warning "Could not stop the PowerShell transcript cleanly."
                $setupExitCode = 2
            }
        }
    }
}
catch {
    Write-Host ""
    Write-Host "[ERROR] Setup stopped."
    Write-Host $_.Exception.Message
    if ($transcriptPath) {
        Write-Host "Log: $transcriptPath"
    }

    if (-not $NoPause) {
        Write-Host "Press Enter to exit."
        [void] [Console]::ReadLine()
    }
    exit 1
}

if (-not $NoPause) {
    Write-Host "Press Enter to exit."
    [void] [Console]::ReadLine()
}

exit $setupExitCode
