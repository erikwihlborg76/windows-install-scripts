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

$elevatedExitCode = Restart-SetupAsAdministrator `
    -ScriptPath $PSCommandPath `
    -BoundParameters $PSBoundParameters

if ($null -ne $elevatedExitCode) {
    exit $elevatedExitCode
}

function Read-SetupChoice {
    param(
        [Parameter(Mandatory)]
        [string] $Caption,

        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory)]
        [string[]] $Labels,

        [Parameter()]
        [int] $DefaultChoice = 0
    )

    $choices = @(
        foreach ($label in $Labels) {
            [Management.Automation.Host.ChoiceDescription]::new($label)
        }
    )

    return $Host.UI.PromptForChoice($Caption, $Message, $choices, $DefaultChoice)
}

try {
    Assert-WinGet

    if (-not (Test-Path -LiteralPath $profileDataPath -PathType Leaf)) {
        throw "Profile configuration was not found: $profileDataPath"
    }
    if (-not (Test-Path -LiteralPath $resourcesRoot -PathType Container)) {
        throw "Resources directory was not found: $resourcesRoot"
    }

    $configuration = Import-PowerShellDataFile -LiteralPath $profileDataPath

    $modeChoice = Read-SetupChoice `
        -Caption "Select setup mode" `
        -Message "Choose whether to apply Windows configuration and install applications." `
        -Labels @(
            "Configure Windows and install &apps"
            "Configure Windows &only - settings and app removal"
            "&Full - author's personal setup, including private sync files"
        ) `
        -DefaultChoice -1

    $Mode = @("CONFIGURE_AND_INSTALL", "CONFIGURE_ONLY", "FULL")[$modeChoice]

    $profileChoice = Read-SetupChoice `
        -Caption "Select profile" `
        -Message "Choose the HOME or WORK configuration overlay." `
        -Labels @("&HOME", "&WORK") `
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
                -Caption "Select sync provider" `
                -Message "Choose the provider containing the Apps and Apps-data folders." `
                -Labels @("OneDrive &Business", "&OneDrive", "&Dropbox")

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
            -Caption "Confirm setup" `
            -Message "Apply this setup plan?" `
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
