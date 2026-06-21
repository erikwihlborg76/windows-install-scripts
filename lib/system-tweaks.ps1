function Disable-NetworkAdapterWake {
    $disabledCount = 0

    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Querying wake-armed network devices."

    try {
        $networkDevices = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        Get-NetAdapter -Physical -IncludeHidden -ErrorAction Stop |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.InterfaceDescription)
            } |
            ForEach-Object {
                [void]$networkDevices.Add($_.InterfaceDescription.Trim())
            }
    }
    catch {
        Write-Warn "Failed to query physical network adapters: $($_.Exception.Message)"
        return
    }

    $wakeArmedDevices = @(
        powercfg.exe -devicequery wake_armed 2>$null |
            ForEach-Object { $_.Trim() } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -ine "NONE"
            }
    )

    foreach ($device in $wakeArmedDevices) {
        if (-not $networkDevices.Contains($device)) {
            Write-LogLine "Leaving non-network wake device enabled: $device"
            continue
        }

        Write-Host "  - Disabling network wake on: `"$device`""
        Write-LogLine "Disabling network wake on: $device"

        & powercfg.exe -devicedisablewake "$device" 1>> $script:Log 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Failed to disable network wake on: $device"
        }
        else {
            $disabledCount++
            Write-Ok "Disabled network wake on: $device"
        }
    }

    if ($disabledCount -eq 0) {
        Write-Ok "No wake-armed network devices found."
    }
}

function Disable-WakeTimers {
    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Disabling wake timers for current power scheme."

    & powercfg.exe /SETACVALUEINDEX SCHEME_CURRENT SUB_SLEEP RTCWAKE 0 1>> $script:Log 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Failed to disable AC wake timers."
    }
    else {
        Write-Ok "Disabled AC wake timers."
    }

    & powercfg.exe /SETDCVALUEINDEX SCHEME_CURRENT SUB_SLEEP RTCWAKE 0 1>> $script:Log 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Failed to disable DC wake timers."
    }
    else {
        Write-Ok "Disabled DC wake timers."
    }

    & powercfg.exe /SETACTIVE SCHEME_CURRENT 1>> $script:Log 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Failed to re-apply current power scheme."
    }
    else {
        Write-Ok "Re-applied current power scheme."
    }
}

function Copy-WindowsTerminalSettings {
    param(
        [Parameter(Mandatory)]
        [string] $ResourcesDir
    )

    Write-Host ""
    Write-Host "========== Windows Terminal =========="

    $wtSettings = Join-Path $ResourcesDir "Windows Terminal\settings.json"

    if (-not (Test-Path -LiteralPath $wtSettings -PathType Leaf)) {
        Write-Warn "Missing Windows Terminal settings: $wtSettings"
        return
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA "Packages"

    $terminalPackages = Get-ChildItem `
        -LiteralPath $packagesRoot `
        -Directory `
        -Filter "Microsoft.WindowsTerminal_*" `
        -ErrorAction SilentlyContinue

    if (-not $terminalPackages) {
        Write-Warn "No Microsoft.WindowsTerminal package folder found."
        return
    }

    foreach ($package in $terminalPackages) {
        $localState = Join-Path $package.FullName "LocalState"
        $destination = Join-Path $localState "settings.json"

        New-Item -ItemType Directory -Path $localState -Force | Out-Null

        try {
            Copy-Item -LiteralPath $wtSettings -Destination $destination -Force
            Write-Ok "Copied Windows Terminal settings to $destination"
        }
        catch {
            Write-Warn "Failed to copy Windows Terminal settings to $destination"
        }
    }
}

function Copy-PowerToysSettings {
    param(
        [Parameter(Mandatory)]
        [string] $SyncRoot
    )

    Write-Host ""
    Write-Host "========== PowerToys settings =========="

    if ([string]::IsNullOrWhiteSpace($SyncRoot)) {
        Write-Info "No sync root supplied; skipping private PowerToys settings."
        return
    }

    $sourceRoot = Join-Path $SyncRoot "Apps-data\PowerToys"
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
        Write-Info "Private PowerToys settings not found, skipping: $sourceRoot"
        return
    }

    Invoke-RoboCopySafe `
        -SourceFolder (Join-Path $sourceRoot "FancyZones") `
        -DestinationFolder (Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones")

    Invoke-RoboCopySafe `
        -SourceFolder (Join-Path $sourceRoot "LightSwitch") `
        -DestinationFolder (Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\LightSwitch")

    $commandPaletteSettings = Join-Path $sourceRoot "CommandPalette\settings.json"
    if (-not (Test-Path -LiteralPath $commandPaletteSettings -PathType Leaf)) {
        Write-Info "Private Command Palette settings not found, skipping: $commandPaletteSettings"
        return
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA "Packages"
    $commandPalettePackages = Get-ChildItem `
        -LiteralPath $packagesRoot `
        -Directory `
        -Filter "Microsoft.CommandPalette_*" `
        -ErrorAction SilentlyContinue

    if (-not $commandPalettePackages) {
        Write-Warn "No Microsoft Command Palette package folder found."
        return
    }

    foreach ($package in $commandPalettePackages) {
        $localState = Join-Path $package.FullName "LocalState"
        $destination = Join-Path $localState "settings.json"

        try {
            New-Item -ItemType Directory -Path $localState -Force | Out-Null
            Copy-Item -LiteralPath $commandPaletteSettings -Destination $destination -Force
            Write-Ok "Copied Command Palette settings to $destination"
        }
        catch {
            Write-Warn "Failed to copy Command Palette settings to $destination. $($_.Exception.Message)"
        }
    }
}

function Set-TweakRegistryValue {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Name,
        [Parameter(Mandatory)][AllowEmptyString()] $Value,
        [Parameter(Mandatory)]
        [ValidateSet("DWord", "String", "ExpandString")]
        [string] $Type
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        if ([string]::IsNullOrEmpty($Name)) {
            Set-Item -LiteralPath $Path -Value $Value -Force
        }
        else {
            New-ItemProperty `
                -LiteralPath $Path `
                -Name $Name `
                -Value $Value `
                -PropertyType $Type `
                -Force | Out-Null
        }
    }
    catch {
        Write-Warn "Failed to set registry value $Path\$Name`: $($_.Exception.Message)"
    }
}

function Disable-TweakScheduledTask {
    param([Parameter(Mandatory)][string] $TaskName)

    & schtasks.exe /Query /TN $TaskName 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Scheduled task not found, skipping: $TaskName"
        return
    }

    & schtasks.exe /Change /TN $TaskName /Disable 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Failed to disable scheduled task: $TaskName"
        return
    }

    Write-Ok "Disabled scheduled task: $TaskName"
}

function Disable-TweakService {
    param([Parameter(Mandatory)][string] $Name)

    & sc.exe query $Name 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Service not found, skipping: $Name"
        return
    }

    & sc.exe config $Name "start=" "disabled" 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Failed to disable service: $Name"
        return
    }

    Write-Ok "Disabled service: $Name"
}

function Invoke-WindowsTweaks {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("HOME", "WORK")]
        [string] $Target
    )

    $isAdministrator = [bool](
        [Security.Principal.WindowsPrincipal]::new(
            [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    )

    if (-not $isAdministrator) {
        throw "Windows tweaks must be run as administrator."
    }

    Write-Host "Applying Windows tweaks..."

    # 1. Input and basic shell behavior
    Set-TweakRegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad" "ScrollDirection" 1 DWord
    Set-TweakRegistryValue "HKCU:\Control Panel\Mouse" "MouseSpeed" "0" String
    Set-TweakRegistryValue "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0" String
    Set-TweakRegistryValue "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0" String
    Set-TweakRegistryValue "HKCU:\Console\%Startup" "DelegationConsole" "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}" String
    Set-TweakRegistryValue "HKCU:\Console\%Startup" "DelegationTerminal" "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}" String

    try {
        Set-WinCultureFromLanguageListOptOut -OptOut $true
        Set-Culture -CultureInfo "sv-SE"
    }
    catch {
        Write-Warn "Failed to set Swedish regional settings: $($_.Exception.Message)"
    }

    # 2. Privacy and telemetry
    # Optional: Disable Recall if present.
    # & dism.exe /Online /Disable-Feature /FeatureName:"Recall"

    Set-TweakRegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" "ShowedToastAtLevel" 0 DWord
    Set-TweakRegistryValue "HKCU:\Software\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" 0 DWord
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0 DWord

    if ($Target -eq "HOME") {
        $enrollmentId = "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
        $enrollmentPath = "HKLM:\SOFTWARE\Microsoft\Enrollments\$enrollmentId"
        $omadmPath = "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\$enrollmentId"

        Set-TweakRegistryValue $enrollmentPath "EnrollmentState" 1 DWord
        Set-TweakRegistryValue $enrollmentPath "EnrollmentType" 0 DWord
        Set-TweakRegistryValue $enrollmentPath "IsFederated" 0 DWord
        Set-TweakRegistryValue $omadmPath "Flags" 14089087 DWord
        Set-TweakRegistryValue $omadmPath "AcctUId" "0x000000000000000000000000000000000000000000000000000000000000000000000000" String
        Set-TweakRegistryValue $omadmPath "RoamingCount" 0 DWord
        Set-TweakRegistryValue $omadmPath "SslClientCertReference" "MY;User;0000000000000000000000000000000000000000" String
        Set-TweakRegistryValue $omadmPath "ProtoVer" "1.2" String
    }

    Set-TweakRegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 0 DWord
    Set-TweakRegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0 DWord
    Set-TweakRegistryValue "HKLM:\Software\Policies\Microsoft\Windows\TabletPC" "PreventHandwritingDataSharing" 1 DWord
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization" "AllowInputPersonalization" 0 DWord
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0 DWord
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" 0 DWord
    Disable-TweakService "WerSvc"
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" "Disabled" 1 DWord

    Disable-TweakScheduledTask "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
    Disable-TweakScheduledTask "Microsoft\Windows\Application Experience\ProgramDataUpdater"
    Disable-TweakScheduledTask "Microsoft\Windows\Application Experience\StartupAppTask"

    # 3. Windows Update behavior
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "NoAutoUpdate" 1 DWord
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 99 DWord

    Disable-TweakScheduledTask "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan"
    Disable-TweakScheduledTask "\Microsoft\Windows\UpdateOrchestrator\Schedule Retry Scan"
    Disable-TweakScheduledTask "\Microsoft\Windows\UpdateOrchestrator\Backup Scan"
    Disable-TweakScheduledTask "Microsoft\Windows\WindowsUpdate\Scheduled Start"

    # 4. Desktop and UI
    Set-TweakRegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarFlashing" 0 DWord
    Set-TweakRegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCopilotButton" 0 DWord
    Set-TweakRegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" 0 DWord
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "HideRecommendedSection" 1 DWord
    # Set-TweakRegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0 DWord
    Set-TweakRegistryValue "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "MultiTaskingAltTabFilter" 4 DWord
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "MultiTaskingAltTabFilter" 4 DWord
    Set-TweakRegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "NavPaneExpandToCurrentFolder" 1 DWord
    Set-TweakRegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" 0 DWord
    Set-TweakRegistryValue "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "0" String
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "AllowOnlineTips" 0 DWord
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "HubMode" 1 DWord
    Set-TweakRegistryValue "HKCU:\Software\Classes\CLSID\{E88865EA-0E1C-4E20-9AA6-EDCD0212C87C}" "System.IsPinnedToNameSpaceTree" 0 DWord
    Set-TweakRegistryValue "HKCU:\Software\Classes\Wow6432Node\CLSID\{E88865EA-0E1C-4E20-9AA6-EDCD0212C87C}" "System.IsPinnedToNameSpaceTree" 0 DWord
    # Set-TweakRegistryValue "HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" "System.IsPinnedToNameSpaceTree" 0 DWord

    # 5. Notifications and system sounds
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" "EnableFeeds" 0 DWord
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "DisableLockScreenAppNotifications" 1 DWord
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "DisableStartupSound" 1 DWord
    Set-TweakRegistryValue "HKCU:\AppEvents\Schemes" "" ".None" String

    try {
        Get-ChildItem -LiteralPath "HKCU:\AppEvents\Schemes\Apps" -Recurse |
            Where-Object { $_.PSChildName -eq ".Current" } |
            ForEach-Object {
                Set-Item -LiteralPath $_.PSPath -Value ""
            }
    }
    catch {
        Write-Warn "Failed to disable one or more system sounds: $($_.Exception.Message)"
    }

    # 6. Search and content delivery
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "DisableWebSearch" 1 DWord
    Set-TweakRegistryValue "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1 DWord
    Set-TweakRegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" 0 DWord
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1 DWord

    # 7. Autorun
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoAutorun" 1 DWord
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun" 255 DWord
    # Set-TweakRegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" "LetAppsRunInBackground" 2 DWord

    # 8. Networking services
    Set-TweakRegistryValue "HKLM:\Software\Policies\Microsoft\Windows\HomeGroup" "DisableHomeGroup" 1 DWord
    Set-TweakRegistryValue "HKLM:\Software\Policies\Microsoft\Peernet" "Disabled" 1 DWord
    Disable-TweakService "CDPSvc"
    Disable-TweakService "CDPUserSvc"

    # 9. Storage and filesystem
    Disable-TweakService "TrkWks"
    Disable-TweakScheduledTask "Microsoft\Windows\DiskFootprint\Diagnostics"
    Disable-TweakScheduledTask "Microsoft\Windows\DiskFootprint\StorageSense"

    if ($Target -eq "HOME") {
        & fsutil.exe behavior set DisableLastAccess 1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Failed to disable last-access timestamp updates."
        }
    }

    # 10. Browser, Store, and cloud
    # Set-TweakRegistryValue "HKLM:\SOFTWARE\Microsoft\OneDrive" "PreventNetworkTrafficPreUserSignIn" 1 DWord
    Set-TweakRegistryValue "HKLM:\Software\Policies\Microsoft\WindowsStore" "AutoDownload" 2 DWord

    # 11. Environment-specific tweaks
    # Disable-TweakService "RetailDemo"
    Set-TweakRegistryValue "Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\open_vscode" "" "Open with Visual Studio Code" String
    Set-TweakRegistryValue "Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\open_vscode\command" "" '"%USERPROFILE%\AppData\Local\Programs\Microsoft VS Code\Code.exe"' ExpandString
    Set-TweakRegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "XMouseButtonControl" "C:\Program Files\Highresolution Enterprises\X-Mouse Button Control\XMouseButtonControl.exe /notportable /delay /NoLog" String

    Write-Host ""
    Write-Ok "Windows tweaks complete."
}

function Import-Lgpo {
    param(
        [Parameter(Mandatory)]
        [string] $ResourcesDir
    )

    Write-Host ""
    Write-Host "========== LGPO import =========="

    $lgpoTxt = Join-Path $ResourcesDir "LGPO\global_policy_objects.txt"

    $lgpoCommand = Get-Command -Name "LGPO.exe" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    $lgpoCandidates = @(
        if ($lgpoCommand) {
            $lgpoCommand.Source
        }

        if ($env:LOCALAPPDATA) {
            Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\LGPO.exe"
        }

        if ($env:ProgramFiles) {
            Join-Path $env:ProgramFiles "WinGet\Links\LGPO.exe"
        }
    )

    $lgpoExe = $lgpoCandidates |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            (Test-Path -LiteralPath $_ -PathType Leaf)
        } |
        Select-Object -First 1

    if (-not $lgpoExe) {
        Write-Warn "LGPO.exe was not found. Install package Microsoft.SecurityComplianceToolkit.LGPO with WinGet."
        return
    }

    if (-not (Test-Path -LiteralPath $lgpoTxt -PathType Leaf)) {
        Write-Warn "LGPO text file not found: $lgpoTxt"
        return
    }

    Write-Host "Importing LGPO settings..."
    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] LGPO import: `"$lgpoTxt`""

    $lgpoStdOut = Join-Path $env:TEMP "LGPO.stdout.log"
    $lgpoStdErr = Join-Path $env:TEMP "LGPO.stderr.log"

    Remove-Item -LiteralPath $lgpoStdOut, $lgpoStdErr -Force -ErrorAction SilentlyContinue

    try {
        $process = Start-Process `
            -FilePath $lgpoExe `
            -ArgumentList @("/t", "`"$lgpoTxt`"") `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $lgpoStdOut `
            -RedirectStandardError $lgpoStdErr

        foreach ($outputFile in @($lgpoStdOut, $lgpoStdErr)) {
            if (Test-Path -LiteralPath $outputFile -PathType Leaf) {
                Get-Content -LiteralPath $outputFile -ErrorAction SilentlyContinue |
                    ForEach-Object { Write-LogLine $_ }
            }
        }

        if ($process.ExitCode -ne 0) {
            Write-Warn "LGPO import failed with exit code $($process.ExitCode). See log: $script:Log"
            return
        }

        Write-Ok "LGPO import completed."
    }
    catch {
        $message = $_.Exception.Message

        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = ($_ | Out-String).Trim()
        }

        Write-Warn "LGPO import failed to start or complete. $message"
    }
}
