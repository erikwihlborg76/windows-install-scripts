function Set-WindowsSettings {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("HOME", "WORK")]
        [string] $Target
    )

    Assert-Administrator

    Write-Host ""
    Write-Host "========== Windows settings =========="

    # 1. Input and basic shell behavior
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad" /v ScrollDirection /t REG_DWORD /d 1 /f
    reg.exe add "HKCU\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d 0 /f
    reg.exe add "HKCU\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d 0 /f
    reg.exe add "HKCU\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d 0 /f
    reg.exe add "HKCU\Console\%Startup" /v DelegationConsole /t REG_SZ /d "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}" /f
    reg.exe add "HKCU\Console\%Startup" /v DelegationTerminal /t REG_SZ /d "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}" /f

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

    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack" /v ShowedToastAtLevel /t REG_DWORD /d 0 /f
    reg.exe add "HKCU\Software\Microsoft\Siuf\Rules" /v NumberOfSIUFInPeriod /t REG_DWORD /d 0 /f
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f

    if ($Target -eq "HOME") {
        $enrollmentId = "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
        $enrollmentPath = "HKLM\SOFTWARE\Microsoft\Enrollments\$enrollmentId"
        $omadmPath = "HKLM\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\$enrollmentId"

        reg.exe add $enrollmentPath /v EnrollmentState /t REG_DWORD /d 1 /f
        reg.exe add $enrollmentPath /v EnrollmentType /t REG_DWORD /d 0 /f
        reg.exe add $enrollmentPath /v IsFederated /t REG_DWORD /d 0 /f
        reg.exe add $omadmPath /v Flags /t REG_DWORD /d 14089087 /f
        reg.exe add $omadmPath /v AcctUId /t REG_SZ /d "0x000000000000000000000000000000000000000000000000000000000000000000000000" /f
        reg.exe add $omadmPath /v RoamingCount /t REG_DWORD /d 0 /f
        reg.exe add $omadmPath /v SslClientCertReference /t REG_SZ /d "MY;User;0000000000000000000000000000000000000000" /f
        reg.exe add $omadmPath /v ProtoVer /t REG_SZ /d "1.2" /f
    }

    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 0 /f
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 0 /f
    reg.exe add "HKLM\Software\Policies\Microsoft\Windows\TabletPC" /v PreventHandwritingDataSharing /t REG_DWORD /d 1 /f
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\InputPersonalization" /v AllowInputPersonalization /t REG_DWORD /d 0 /f
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v PublishUserActivities /t REG_DWORD /d 0 /f
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v UploadUserActivities /t REG_DWORD /d 0 /f
    Disable-Service "WerSvc"
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" /v Disabled /t REG_DWORD /d 1 /f

    Disable-ScheduledTaskByName "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
    Disable-ScheduledTaskByName "Microsoft\Windows\Application Experience\ProgramDataUpdater"
    Disable-ScheduledTaskByName "Microsoft\Windows\Application Experience\StartupAppTask"

    # 3. Windows Update behavior
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 99 /f

    Disable-ScheduledTaskByName "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan"
    Disable-ScheduledTaskByName "\Microsoft\Windows\UpdateOrchestrator\Schedule Retry Scan"
    Disable-ScheduledTaskByName "\Microsoft\Windows\UpdateOrchestrator\Backup Scan"
    Disable-ScheduledTaskByName "Microsoft\Windows\WindowsUpdate\Scheduled Start"

    # 4. Desktop and UI
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarFlashing /t REG_DWORD /d 0 /f
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowCopilotButton /t REG_DWORD /d 0 /f
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowTaskViewButton /t REG_DWORD /d 0 /f
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v HideRecommendedSection /t REG_DWORD /d 1 /f
    # reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f
    reg.exe add "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v MultiTaskingAltTabFilter /t REG_DWORD /d 4 /f
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v MultiTaskingAltTabFilter /t REG_DWORD /d 4 /f
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v NavPaneExpandToCurrentFolder /t REG_DWORD /d 1 /f
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarAnimations /t REG_DWORD /d 0 /f
    reg.exe add "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d 0 /f
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v AllowOnlineTips /t REG_DWORD /d 0 /f
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" /v HubMode /t REG_DWORD /d 1 /f
    reg.exe add "HKCU\Software\Classes\CLSID\{E88865EA-0E1C-4E20-9AA6-EDCD0212C87C}" /v System.IsPinnedToNameSpaceTree /t REG_DWORD /d 0 /f
    reg.exe add "HKCU\Software\Classes\Wow6432Node\CLSID\{E88865EA-0E1C-4E20-9AA6-EDCD0212C87C}" /v System.IsPinnedToNameSpaceTree /t REG_DWORD /d 0 /f
    # reg.exe add "HKCU\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" /v System.IsPinnedToNameSpaceTree /t REG_DWORD /d 0 /f

    # 5. Notifications and system sounds
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" /v EnableFeeds /t REG_DWORD /d 0 /f
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v DisableLockScreenAppNotifications /t REG_DWORD /d 1 /f
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableStartupSound /t REG_DWORD /d 1 /f
    reg.exe add "HKCU\AppEvents\Schemes" /ve /t REG_SZ /d ".None" /f

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
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v DisableWebSearch /t REG_DWORD /d 1 /f
    reg.exe add "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 1 /f
    reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" /v SearchboxTaskbarMode /t REG_DWORD /d 0 /f
    reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f

    # 7. Autorun
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoAutorun /t REG_DWORD /d 1 /f
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoDriveTypeAutoRun /t REG_DWORD /d 255 /f
    # reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /v LetAppsRunInBackground /t REG_DWORD /d 2 /f

    # 8. Networking services
    reg.exe add "HKLM\Software\Policies\Microsoft\Windows\HomeGroup" /v DisableHomeGroup /t REG_DWORD /d 1 /f
    reg.exe add "HKLM\Software\Policies\Microsoft\Peernet" /v Disabled /t REG_DWORD /d 1 /f
    Disable-Service "CDPSvc"
    Disable-Service "CDPUserSvc"

    # 9. Storage and filesystem
    Disable-Service "TrkWks"
    Disable-ScheduledTaskByName "Microsoft\Windows\DiskFootprint\Diagnostics"
    Disable-ScheduledTaskByName "Microsoft\Windows\DiskFootprint\StorageSense"

    if ($Target -eq "HOME") {
        & fsutil.exe behavior set DisableLastAccess 1
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Failed to disable last-access timestamp updates."
        }
    }

    # 10. Browser, Store, and cloud
    # reg.exe add "HKLM\SOFTWARE\Microsoft\OneDrive" /v PreventNetworkTrafficPreUserSignIn /t REG_DWORD /d 1 /f
    reg.exe add "HKLM\Software\Policies\Microsoft\WindowsStore" /v AutoDownload /t REG_DWORD /d 2 /f

    # 11. Environment-specific settings
    # Disable-Service "RetailDemo"
    reg.exe add "HKCR\Directory\Background\shell\open_vscode" /ve /t REG_SZ /d "Open with Visual Studio Code" /f
    reg.exe add "HKCR\Directory\Background\shell\open_vscode\command" /ve /t REG_EXPAND_SZ /d '"%USERPROFILE%\AppData\Local\Programs\Microsoft VS Code\Code.exe"' /f
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v XMouseButtonControl /t REG_SZ /d "C:\Program Files\Highresolution Enterprises\X-Mouse Button Control\XMouseButtonControl.exe /notportable /delay /NoLog" /f

    Write-Host ""
    Write-Ok "Windows settings complete."
}
