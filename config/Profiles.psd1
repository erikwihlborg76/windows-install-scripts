@{
    Common = @{
        PackageManifest = "packages.common.json"

        Registry = @(
            # Mouse and touchpad
            @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad";                         Name = "ScrollDirection";                              Type = "DWord";        Value = 1 }
            @{ Path = "HKCU:\Control Panel\Mouse";                                                                 Name = "MouseSpeed";                                   Type = "String";       Value = "0" }
            @{ Path = "HKCU:\Control Panel\Mouse";                                                                 Name = "MouseThreshold1";                              Type = "String";       Value = "0" }
            @{ Path = "HKCU:\Control Panel\Mouse";                                                                 Name = "MouseThreshold2";                              Type = "String";       Value = "0" }

            # Default terminal application
            @{ Path = "HKCU:\Console\%%Startup";                                                                   Name = "DelegationConsole";                            Type = "String";       Value = "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}" }
            @{ Path = "HKCU:\Console\%%Startup";                                                                   Name = "DelegationTerminal";                           Type = "String";       Value = "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}" }

            # Privacy, diagnostics, and feedback
            @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack";                     Name = "ShowedToastAtLevel";                           Type = "DWord";        Value = 0 }
            @{ Path = "HKCU:\Software\Microsoft\Siuf\Rules";                                                       Name = "NumberOfSIUFInPeriod";                         Type = "DWord";        Value = 0 }
            @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy";                                   Name = "TailoredExperiencesWithDiagnosticDataEnabled"; Type = "DWord";        Value = 0 }
            @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo";                           Name = "Enabled";                                      Type = "DWord";        Value = 0 }
            @{ Path = "HKLM:\Software\Policies\Microsoft\Windows\TabletPC";                                        Name = "PreventHandwritingDataSharing";                Type = "DWord";        Value = 1 }
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization";                                    Name = "AllowInputPersonalization";                    Type = "DWord";        Value = 0 }
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                                          Name = "PublishUserActivities";                        Type = "DWord";        Value = 0 }
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                                          Name = "UploadUserActivities";                         Type = "DWord";        Value = 0 }
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting";                         Name = "Disabled";                                     Type = "DWord";        Value = 1 }

            # Windows Update, Delivery Optimization, and Store updates
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU";                                Name = "NoAutoUpdate";                                 Type = "DWord";        Value = 1 }
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization";                            Name = "DODownloadMode";                               Type = "DWord";        Value = 99 }
            @{ Path = "HKLM:\Software\Policies\Microsoft\WindowsStore";                                            Name = "AutoDownload";                                 Type = "DWord";        Value = 2 }

            # Start menu, taskbar, suggestions, and notifications
            @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";                         Name = "TaskbarFlashing";                              Type = "DWord";        Value = 0 }
            @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";                         Name = "ShowCopilotButton";                            Type = "DWord";        Value = 0 }
            @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";                         Name = "ShowTaskViewButton";                           Type = "DWord";        Value = 0 }
            @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";                         Name = "Start_IrisRecommendations";                    Type = "DWord";        Value = 0 }
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer";                                        Name = "HideRecommendedSection";                       Type = "DWord";        Value = 1 }
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer";                         Name = "AllowOnlineTips";                              Type = "DWord";        Value = 0 }
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System";                                          Name = "DisableLockScreenAppNotifications";            Type = "DWord";        Value = 1 }
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent";                                    Name = "DisableWindowsConsumerFeatures";               Type = "DWord";        Value = 1 }

            # Multitasking and animations
            @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\Explorer";                                        Name = "MultiTaskingAltTabFilter";                     Type = "DWord";        Value = 4 }
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer";                                        Name = "MultiTaskingAltTabFilter";                     Type = "DWord";        Value = 4 }
            @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";                         Name = "TaskbarAnimations";                            Type = "DWord";        Value = 0 }
            @{ Path = "HKCU:\Control Panel\Desktop\WindowMetrics";                                                 Name = "MinAnimate";                                   Type = "String";       Value = "0" }

            # File Explorer navigation
            @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced";                         Name = "NavPaneExpandToCurrentFolder";                 Type = "DWord";        Value = 1 }
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer";                                  Name = "HubMode";                                      Type = "DWord";        Value = 1 }
            @{ Path = "HKCU:\Software\Classes\CLSID\{E88865EA-0E1C-4E20-9AA6-EDCD0212C87C}";                       Name = "System.IsPinnedToNameSpaceTree";               Type = "DWord";        Value = 0 }
            @{ Path = "HKCU:\Software\Classes\Wow6432Node\CLSID\{E88865EA-0E1C-4E20-9AA6-EDCD0212C87C}";           Name = "System.IsPinnedToNameSpaceTree";               Type = "DWord";        Value = 0 }

            # Windows Search
            @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search";                                  Name = "DisableWebSearch";                             Type = "DWord";        Value = 1 }
            @{ Path = "HKCU:\Software\Policies\Microsoft\Windows\Explorer";                                        Name = "DisableSearchBoxSuggestions";                  Type = "DWord";        Value = 1 }
            @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search";                                    Name = "SearchboxTaskbarMode";                         Type = "DWord";        Value = 0 }

            # System sounds
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System";                           Name = "DisableStartupSound";                          Type = "DWord";        Value = 1 }
            @{ Path = "HKCU:\AppEvents\Schemes";                                                                   Name = "";                                             Type = "String";       Value = ".None" }

            # AutoRun
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer";                         Name = "NoAutorun";                                    Type = "DWord";        Value = 1 }
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer";                         Name = "NoDriveTypeAutoRun";                           Type = "DWord";        Value = 255 }
        )

        # Applied only when installing the application bundle.
        ApplicationRegistry = @(
            # File Explorer context menu for Visual Studio Code
            @{ Path = "Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\open_vscode";                        Name = "";                                             Type = "String";       Value = "Open with Visual Studio Code" }
            @{ Path = "Registry::HKEY_CLASSES_ROOT\Directory\Background\shell\open_vscode\command";                Name = "";                                             Type = "ExpandString"; Value = '"%USERPROFILE%\AppData\Local\Programs\Microsoft VS Code\Code.exe"' }
        )

        ServicesToDisable = @(
            "WerSvc"
            "CDPSvc"
            "CDPUserSvc"
            "TrkWks"
        )

        ScheduledTasksToDisable = @(
            # Optional Lenovo task that can wake the computer.
            @{ TaskPath = "\"; TaskName = "LvfGuiRemoval" }
            @{ TaskPath = "\Microsoft\Windows\Application Experience\"; TaskName = "Microsoft Compatibility Appraiser" }
            @{ TaskPath = "\Microsoft\Windows\Application Experience\"; TaskName = "ProgramDataUpdater" }
            @{ TaskPath = "\Microsoft\Windows\Application Experience\"; TaskName = "StartupAppTask" }
            @{ TaskPath = "\Microsoft\Windows\UpdateOrchestrator\"; TaskName = "Schedule Scan" }
            @{ TaskPath = "\Microsoft\Windows\UpdateOrchestrator\"; TaskName = "Schedule Retry Scan" }
            @{ TaskPath = "\Microsoft\Windows\UpdateOrchestrator\"; TaskName = "Backup Scan" }
            @{ TaskPath = "\Microsoft\Windows\WindowsUpdate\"; TaskName = "Scheduled Start" }
            @{ TaskPath = "\Microsoft\Windows\DiskFootprint\"; TaskName = "Diagnostics" }
            @{ TaskPath = "\Microsoft\Windows\DiskFootprint\"; TaskName = "StorageSense" }
        )

        AppxRemovals = @(
            @{ Pattern = "*WindowsSoundRecorder*"; Label = "Windows Sound Recorder" }
            @{ Pattern = "*WindowsAlarms*"; Label = "Windows Clock" }
            @{ Pattern = "*PowerAutomateDesktop*"; Label = "Power Automate" }
            @{ Pattern = "*GetHelp*"; Label = "Get Help" }
            @{ Pattern = "*Copilot*"; Label = "Copilot" }
            @{ Pattern = "*XboxSpeechToTextOverlay*"; Label = "Game Speech Window" }
            @{ Pattern = "*YourPhone*"; Label = "Phone Link" }
            @{ Pattern = "*Xbox.TCUI*"; Label = "Xbox TCUI" }
            @{ Pattern = "*CrossDevice*"; Label = "Cross Device Experience Host" }
            @{ Pattern = "*QuickAssist*"; Label = "Quick Assist" }
            @{ Pattern = "*BingNews*"; Label = "Microsoft News" }
            @{ Pattern = "*BingSearch*"; Label = "Microsoft Bing Search" }
            @{ Pattern = "*BingWeather*"; Label = "MSN Weather" }
            @{ Pattern = "*GamingApp*"; Label = "Xbox" }
            @{ Pattern = "*Solitaire*"; Label = "Solitaire & Casual Games" }
            @{ Pattern = "*StickyNotes*"; Label = "Microsoft Sticky Notes" }
            @{ Pattern = "*Paint*"; Label = "Paint" }
            @{ Pattern = "*Todos*"; Label = "Microsoft To Do" }
            @{ Pattern = "*WindowsFeedbackHub*"; Label = "Feedback Hub" }
            @{ Pattern = "*XboxIdentityProvider*"; Label = "Xbox Identity Provider" }
            @{ Pattern = "*ZuneMusic*"; Label = "Windows Media Player" }
            @{ Pattern = "*OutlookForWindows*"; Label = "Outlook for Windows" }
            @{ Pattern = "*Clipchamp*"; Label = "Microsoft Clipchamp" }
        )

        WingetNameRemovals = @(
            "Widgets Platform Runtime"
            "Microsoft Bing"
            "Start Experiences App"
            "Microsoft Edge Game Assist"
            "Microsoft 365 Copilot"
        )

        CapabilitiesToRemove = @(
            # Keep Snipping Tool installed; uncomment to remove this capability.
            # @{ Name = "Microsoft.Windows.SnippingTool~~~~0.0.1.0"; Label = "Snipping Tool" }
        )
    }

    HOME = @{
        BootLabel = "Home"
        PromptForComputerName = $true
        VirtualDesktopNames = @()
        AdditionalPackageManifests = @()
        AdditionalWingetNameRemovals = @("Microsoft Teams")
        Registry = @(
            # Placeholder MDM enrollment
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Enrollments\FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF";                 Name = "EnrollmentState";                              Type = "DWord";        Value = 1 }
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Enrollments\FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF";                 Name = "EnrollmentType";                               Type = "DWord";        Value = 0 }
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Enrollments\FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF";                 Name = "IsFederated";                                  Type = "DWord";        Value = 0 }

            # Placeholder MDM account provisioning
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"; Name = "Flags";                                        Type = "DWord";        Value = 14089087 }
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"; Name = "AcctUId";                                      Type = "String";       Value = "0x000000000000000000000000000000000000000000000000000000000000000000000000" }
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"; Name = "RoamingCount";                                 Type = "DWord";        Value = 0 }
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"; Name = "SslClientCertReference";                       Type = "String";       Value = "MY;User;0000000000000000000000000000000000000000" }
            @{ Path = "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts\FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"; Name = "ProtoVer";                                     Type = "String";       Value = "1.2" }
        )
    }

    WORK = @{
        BootLabel = "Work"
        PromptForComputerName = $false
        VirtualDesktopNames = @("Plan", "Work", "Meet", "Play")
        AdditionalPackageManifests = @("packages.work.json")
        AdditionalWingetNameRemovals = @()
        Registry = @()
    }
}
