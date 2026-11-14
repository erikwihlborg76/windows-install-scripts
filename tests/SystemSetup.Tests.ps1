BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psd1") -Force
}

Describe "SystemSetup public surface" {
    It "exports only the phase-level commands" {
        $expected = @(
            "Assert-WinGet", "Install-Applications", "Invoke-SystemConfiguration",
            "Remove-UnwantedSoftware", "Restart-SetupAsAdministrator", "Set-RepositoryApplicationDefaults",
            "Set-RepositoryFancyZonesLayout"
        )
        $actual = @(Get-Command -Module SystemSetup | Select-Object -ExpandProperty Name | Sort-Object)
        $actual | Should -Be ($expected | Sort-Object)
    }
}

Describe "Registry settings" {
    It "preserves unrelated values and descendants when typed settings are reapplied" {
        InModuleScope SystemSetup {
            $path = "TestRegistry:\Preserved"
            New-Item -Path "$path\Child" -Force | Out-Null
            New-ItemProperty -Path $path -Name "Unrelated" -Value "keep" -PropertyType String | Out-Null
            $settings = @(
                @{ Path = $path; Name = "First"; Type = "DWord"; Value = 1 }
                @{ Path = $path; Name = "Second"; Type = "String"; Value = "two" }
                @{ Path = $path; Name = ""; Type = "ExpandString"; Value = '%USERPROFILE%\Example' }
            )

            Set-ConfiguredRegistryValues -Settings $settings
            Set-ConfiguredRegistryValues -Settings $settings

            $key = Get-Item -LiteralPath $path
            try {
                $key.GetValue("Unrelated") | Should -Be "keep"
                $key.GetValue("First") | Should -Be 1
                $key.GetValueKind("First") | Should -Be "DWord"
                $key.GetValue("Second") | Should -Be "two"
                $key.GetValueKind("Second") | Should -Be "String"
                $key.GetValue("", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) |
                    Should -Be '%USERPROFILE%\Example'
                $key.GetValueKind("") | Should -Be "ExpandString"
            }
            finally {
                $key.Dispose()
            }
            Test-Path -LiteralPath "$path\Child" | Should -BeTrue
        }
    }

    It "creates missing nested keys and updates an existing value's type" {
        InModuleScope SystemSetup {
            $path = "TestRegistry:\Missing\Nested"
            Set-ConfiguredRegistryValues -Settings @(
                @{ Path = $path; Name = "Value"; Type = "String"; Value = "old" }
            )
            Set-ConfiguredRegistryValues -Settings @(
                @{ Path = $path; Name = "Value"; Type = "DWord"; Value = 3 }
            )
            $key = Get-Item -LiteralPath $path
            try {
                $key.GetValue("Value") | Should -Be 3
                $key.GetValueKind("Value") | Should -Be "DWord"
            }
            finally {
                $key.Dispose()
            }
        }
    }
}

Describe "Native command results" {
    It "accepts stderr diagnostics with a zero exit code under ErrorActionPreference Stop" {
        InModuleScope SystemSetup {
            $ErrorActionPreference = "Stop"
            $result = Invoke-SetupNativeCommand -FilePath $env:ComSpec -Arguments @(
                "/d", "/c", "echo diagnostic 1>&2 & exit /b 0"
            )

            @($result).Count | Should -Be 1
            $result.ExitCode | Should -Be 0
            ($result.Output -join " ") | Should -Match "diagnostic"
            $result.Output[0] | Should -BeOfType string
            $ErrorActionPreference | Should -Be "Stop"
        }
    }

    It "returns nonzero exit codes and captured output without throwing on stderr" {
        InModuleScope SystemSetup {
            $ErrorActionPreference = "Stop"
            $result = Invoke-SetupNativeCommand -FilePath $env:ComSpec -Arguments @(
                "/d", "/c", "echo output & echo diagnostic 1>&2 & exit /b 37"
            )

            $result.ExitCode | Should -Be 37
            ($result.Output -join " ") | Should -Match "output"
            ($result.Output -join " ") | Should -Match "diagnostic"
        }
    }

    It "throws for a missing executable instead of reusing an earlier exit code" {
        InModuleScope SystemSetup {
            $LASTEXITCODE = 0
            { Invoke-SetupNativeCommand -FilePath "codex-nonexistent-native-tool-947d.exe" } | Should -Throw
        }
    }

    It "keeps LGPO diagnostics off the success stream and rejects failed imports" {
        InModuleScope SystemSetup {
            Mock Test-Path { $true }
            Mock Install-LgpoIfMissing { "LGPO.exe" }
            Mock Invoke-SetupNativeCommand {
                [pscustomobject] @{ ExitCode = 0; Output = @("LGPO diagnostic") }
            }
            @(Import-LgpoPolicy -ResourcesRoot "C:\Resources").Count | Should -Be 0

            Mock Invoke-SetupNativeCommand {
                [pscustomobject] @{ ExitCode = 7; Output = @("LGPO failed") }
            }
            { Import-LgpoPolicy -ResourcesRoot "C:\Resources" } | Should -Throw "*exit code 7*"
        }
    }
}

Describe "WinGet configuration guards" {
    It "applies application registry settings after successful package imports" {
        InModuleScope SystemSetup -Parameters @{ Root = $repositoryRoot } {
            param($Root)
            Mock Assert-WinGet {}
            Mock Install-WinGetManifest {}
            Mock Set-ConfiguredRegistryValues {}
            Mock Test-WindowsActivation {}
            $profiles = Import-PowerShellDataFile -LiteralPath (Join-Path $Root "config\Profiles.psd1")

            Install-Applications -ConfigRoot (Join-Path $Root "config") `
                -CommonConfiguration $profiles.Common -ProfileConfiguration $profiles.WORK

            Should -Invoke Install-WinGetManifest -Times 2 -Exactly
            Should -Invoke Set-ConfiguredRegistryValues -Times 1 -Exactly -ParameterFilter {
                $Settings.Count -eq 2 -and $Settings[0].Path -like '*\open_vscode' -and
                $Settings[1].Path -like '*\open_vscode\command'
            }
        }
    }

    It "does not register application integration when package installation fails" {
        InModuleScope SystemSetup -Parameters @{ Root = $repositoryRoot } {
            param($Root)
            Mock Assert-WinGet {}
            Mock Install-WinGetManifest { throw "Package import failed" }
            Mock Set-ConfiguredRegistryValues {}
            Mock Test-WindowsActivation {}
            $profiles = Import-PowerShellDataFile -LiteralPath (Join-Path $Root "config\Profiles.psd1")

            { Install-Applications -ConfigRoot (Join-Path $Root "config") `
                -CommonConfiguration $profiles.Common -ProfileConfiguration $profiles.WORK } |
                Should -Throw '*Package import failed*'

            Should -Invoke Set-ConfiguredRegistryValues -Times 0 -Exactly
        }
    }

    It "throws recovery instructions when WinGet is unavailable" {
        InModuleScope SystemSetup {
            Mock Test-WinGetAvailable { $false }
            { Assert-WinGet } | Should -Throw "*wsreset -i*Install App Installer*"
        }
    }

    It "rejects blank manifest names before installing any package" {
        InModuleScope SystemSetup {
            Mock Assert-WinGet {}
            Mock Install-WinGetManifest {}
            Mock Test-WindowsActivation {}

            foreach ($name in @("", " ")) {
                { Install-Applications -ConfigRoot "C:\Config" -CommonConfiguration @{ PackageManifest = $name } -ProfileConfiguration @{ AdditionalPackageManifests = @() } } |
                    Should -Throw "*Invalid WinGet package manifest name*"
            }
            Should -Invoke Install-WinGetManifest -Times 0
            Should -Invoke Test-WindowsActivation -Times 0
        }
    }

    It "checks every selected manifest before installing the first" {
        InModuleScope SystemSetup {
            Mock Assert-WinGet {}
            Mock Install-WinGetManifest {}
            Mock Test-WindowsActivation {}
            Mock Test-Path { $LiteralPath -eq "C:\Config\packages.common.json" }

            { Install-Applications -ConfigRoot "C:\Config" -CommonConfiguration @{ PackageManifest = "packages.common.json" } -ProfileConfiguration @{ AdditionalPackageManifests = @("packages.work.json") } } |
                Should -Throw "*manifest was not found*packages.work.json*"
            Should -Invoke Install-WinGetManifest -Times 0
            Should -Invoke Test-WindowsActivation -Times 0
        }
    }
}

Describe "Elevation handoff" {
    It "preserves literal paths and switches, waits, and propagates the child exit code" {
        $childDirectory = Join-Path $TestDrive "Setup's files"
        New-Item -Path $childDirectory -ItemType Directory | Out-Null
        $childPath = Join-Path $childDirectory "Install.ps1"
        $resultPath = Join-Path $TestDrive "arguments.json"
        $childScript = @'
param([string] $Profile, [string] $SyncRoot, [switch] $NoPause, [switch] $SkipConfirmation)
[pscustomobject] @{
    Profile = $Profile
    SyncRoot = $SyncRoot
    NoPause = $NoPause.IsPresent
    SkipConfirmation = $SkipConfirmation.IsPresent
} | ConvertTo-Json | Set-Content -LiteralPath '__RESULT_PATH__'
exit 23
'@
        $childScript.Replace("__RESULT_PATH__", $resultPath.Replace("'", "''")) |
            Set-Content -LiteralPath $childPath

        InModuleScope SystemSetup -Parameters @{ ChildPath = $childPath } {
            param($ChildPath)
            Mock Test-SetupAdministrator { $false }
            Mock Start-Process {
                # Only this harmless TestDrive script runs; elevation is mocked.
                & powershell.exe @($ArgumentList -split " ")
                [pscustomobject] @{ ExitCode = $LASTEXITCODE }
            }
            $exitCode = Restart-SetupAsAdministrator -ScriptPath $ChildPath -BoundParameters @{
                Profile = "WORK"
                SyncRoot = 'C:\Erik''s $files\cloud\'
                NoPause = [Management.Automation.SwitchParameter]::new($true)
                SkipConfirmation = [Management.Automation.SwitchParameter]::new($false)
            }
            $exitCode | Should -Be 23
            Should -Invoke Start-Process -Exactly 1 -ParameterFilter {
                $FilePath -eq "powershell.exe" -and $Verb -eq "RunAs" -and $Wait -and $PassThru
            }
        }

        $arguments = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        $arguments.Profile | Should -Be "WORK"
        $arguments.SyncRoot | Should -Be 'C:\Erik''s $files\cloud\'
        $arguments.NoPause | Should -BeTrue
        $arguments.SkipConfirmation | Should -BeFalse
    }

    It "does not restart an already elevated process" {
        InModuleScope SystemSetup {
            Mock Test-SetupAdministrator { $true }
            Mock Start-Process { throw "Should not launch" }

            Restart-SetupAsAdministrator -ScriptPath "C:\Install.ps1" | Should -BeNullOrEmpty
            Should -Invoke Start-Process -Times 0
        }
    }
}

Describe "Absent resources and query failures" {
    It "skips absent services but warns when service enumeration fails" {
        InModuleScope SystemSetup {
            Mock Get-Service { @() }
            Mock Set-Service {}
            Mock Write-Host {}
            Mock Write-Warning {}

            Disable-ConfiguredServices -Names @("AbsentService")
            Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -like "*SKIP*AbsentService*" }
            Should -Invoke Write-Warning -Times 0
            Should -Invoke Set-Service -Times 0

            Mock Get-Service { throw "Service query denied" }
            Disable-ConfiguredServices -Names @("AbsentService")
            Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like "*Service query denied*" }
        }
    }

    It "skips absent tasks but warns when task enumeration fails" {
        InModuleScope SystemSetup {
            Mock Get-ScheduledTask { @() }
            Mock Disable-ScheduledTask {}
            Mock Write-Host {}
            Mock Write-Warning {}
            $tasks = @(@{ TaskPath = "\Example\"; TaskName = "AbsentTask" })

            Disable-ConfiguredScheduledTasks -Tasks $tasks
            Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -like "*SKIP*AbsentTask*" }
            Should -Invoke Write-Warning -Times 0
            Should -Invoke Disable-ScheduledTask -Times 0

            Mock Get-ScheduledTask { throw "Task query denied" }
            Disable-ConfiguredScheduledTasks -Tasks $tasks
            Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like "*Task query denied*" }
        }
    }

    It "does not misreport a failed AppX query as an absent package" {
        InModuleScope SystemSetup {
            Mock Get-AppxPackage { throw "AppX query denied" }
            Mock Get-AppxProvisionedPackage { @() }
            Mock Remove-AppxPackage {}
            Mock Remove-AppxProvisionedPackage {}
            Mock Write-Host {}
            Mock Write-Warning {}

            Remove-AppxPattern -Pattern "*Example*" -Label "Example"
            Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like "*AppX query denied*" }
            Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -like "*SKIP*" }
            Should -Invoke Remove-AppxPackage -Times 0
            Should -Invoke Remove-AppxProvisionedPackage -Times 0
        }
    }

    It "treats WinGet's package-not-found code as a skip and other errors as failures" {
        InModuleScope SystemSetup {
            Mock Write-Host {}
            Mock Write-Warning {}
            Mock Invoke-SetupNativeCommand {
                [pscustomobject] @{ ExitCode = -1978335212; Output = @() }
            }

            Uninstall-WinGetName -Name "Absent App"
            Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -like "*SKIP*Absent App*" }
            Should -Invoke Write-Warning -Times 0

            Mock Invoke-SetupNativeCommand {
                [pscustomobject] @{ ExitCode = 5; Output = @() }
            }
            Uninstall-WinGetName -Name "Broken App"
            Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like "*exit code 5*" }
        }
    }
}
