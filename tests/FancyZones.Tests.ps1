BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psd1") -Force
}

Describe "FancyZones layout application" {
    BeforeEach {
        $savedLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
        $localLayouts = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones\custom-layouts.json"
        New-Item -ItemType Directory -Path (Split-Path $localLayouts) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repositoryRoot "resources\PowerToys\FancyZones\custom-layouts.json") -Destination $localLayouts
        Mock Get-FancyZonesCliPath -ModuleName SystemSetup { 'C:\fixture\PowerToys\bin\PowerToys.FancyZones.CLI.exe' }
        Mock Get-VirtualDesktopTool -ModuleName SystemSetup { 'VirtualDesktop11-24H2.exe' }
        Mock Start-FancyZonesForSetup -ModuleName SystemSetup {}
        Mock Start-Sleep -ModuleName SystemSetup {}
        Mock Write-Warning -ModuleName SystemSetup {}
        InModuleScope SystemSetup {
            $script:fixtureDesktopCount = 4
            $script:fixtureActiveDesktop = 2
            $script:fixtureLayoutFailure = -1
            $script:fixtureAppliedDesktops = [Collections.Generic.List[int]]::new()
            Mock Invoke-SetupNativeCommand {
                if ($FilePath -like '*PowerToys.FancyZones.CLI.exe') {
                    $script:fixtureAppliedDesktops.Add($script:fixtureActiveDesktop)
                    $status = if ($script:fixtureLayoutFailure -eq $script:fixtureActiveDesktop) { 1 } else { 0 }
                    return [pscustomobject] @{ ExitCode = $status; Output = @('layout command') }
                }
                if ($Arguments -contains '/Count') {
                    return [pscustomobject] @{ ExitCode = $script:fixtureDesktopCount; Output = @() }
                }
                if ($Arguments -contains '/GetCurrentDesktop') {
                    return [pscustomobject] @{ ExitCode = $script:fixtureActiveDesktop; Output = @() }
                }
                $switch = @($Arguments | Where-Object { $_ -like '/Switch:*' })
                if ($switch.Count -ne 1) { throw 'Unexpected desktop command in fixture.' }
                $script:fixtureActiveDesktop = [int] $switch[0].Substring(8)
                return [pscustomobject] @{ ExitCode = $script:fixtureActiveDesktop; Output = @() }
            }
        }
    }

    AfterEach { $env:LOCALAPPDATA = $savedLocalAppData }

    It "applies the saved UUID to every monitor on every desktop and restores the original desktop" {
        Set-RepositoryFancyZonesLayout -ResourcesRoot (Join-Path $repositoryRoot "resources")
        InModuleScope SystemSetup {
            @($script:fixtureAppliedDesktops) | Should -Be @(0, 1, 2, 3)
            $script:fixtureActiveDesktop | Should -Be 2
            Should -Invoke Invoke-SetupNativeCommand -Times 4 -Exactly -ParameterFilter {
                $FilePath -like '*PowerToys.FancyZones.CLI.exe' -and $Arguments.Count -eq 3 -and
                $Arguments[0] -eq 'set-layout' -and $Arguments[1] -eq '{EF0B1504-D1C0-4598-9379-ED52A2CA9CDB}' -and
                $Arguments[2] -eq '--all'
            }
            Should -Invoke Write-Warning -Times 0 -Exactly
        }
    }

    It "restores the starting desktop if a layout command fails" {
        InModuleScope SystemSetup { $script:fixtureLayoutFailure = 1 }
        Set-RepositoryFancyZonesLayout -ResourcesRoot (Join-Path $repositoryRoot "resources")
        InModuleScope SystemSetup {
            @($script:fixtureAppliedDesktops) | Should -Be @(0, 1)
            $script:fixtureActiveDesktop | Should -Be 2
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*FancyZones failed on virtual desktop 1*' }
        }
    }

    It "does not switch desktops when there is only one" {
        InModuleScope SystemSetup {
            $script:fixtureDesktopCount = 1
            $script:fixtureActiveDesktop = 0
        }
        Set-RepositoryFancyZonesLayout -ResourcesRoot (Join-Path $repositoryRoot "resources")
        InModuleScope SystemSetup {
            @($script:fixtureAppliedDesktops) | Should -Be @(0)
            Should -Invoke Invoke-SetupNativeCommand -Times 0 -Exactly -ParameterFilter {
                @($Arguments | Where-Object { $_ -like '/Switch:*' }).Count -gt 0
            }
        }
    }

    It "skips layout application when PowerToys or the CLI is absent" {
        Mock Get-FancyZonesCliPath -ModuleName SystemSetup { $null }
        Set-RepositoryFancyZonesLayout -ResourcesRoot (Join-Path $repositoryRoot "resources")
        Should -Invoke Get-VirtualDesktopTool -ModuleName SystemSetup -Times 0 -Exactly
        Should -Invoke Invoke-SetupNativeCommand -ModuleName SystemSetup -Times 0 -Exactly
        Should -Invoke Write-Warning -ModuleName SystemSetup -Times 1 -Exactly -ParameterFilter { $Message -like '*CLI was not found*' }
    }

    It "does not start PowerToys or change desktops if the saved layout was not imported" {
        [IO.File]::WriteAllText($localLayouts, '{"custom-layouts":[]}')
        Set-RepositoryFancyZonesLayout -ResourcesRoot (Join-Path $repositoryRoot "resources")
        Should -Invoke Get-VirtualDesktopTool -ModuleName SystemSetup -Times 0 -Exactly
        Should -Invoke Start-FancyZonesForSetup -ModuleName SystemSetup -Times 0 -Exactly
        Should -Invoke Invoke-SetupNativeCommand -ModuleName SystemSetup -Times 0 -Exactly
        Should -Invoke Write-Warning -ModuleName SystemSetup -Times 1 -Exactly -ParameterFilter { $Message -like '*layout was not imported*' }
    }
}

Describe "FancyZones CLI discovery and startup" {
    It "finds a newly installed per-user CLI even when PATH has not been refreshed" {
        $savedLocalAppData = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = Join-Path $TestDrive 'new-user-install'
            $cli = Join-Path $env:LOCALAPPDATA 'PowerToys\bin\PowerToys.FancyZones.CLI.exe'
            New-Item -ItemType Directory -Path (Split-Path $cli) -Force | Out-Null
            [IO.File]::WriteAllText($cli, 'fixture; never executed')
            Mock Get-Command -ModuleName SystemSetup { $null }
            InModuleScope SystemSetup -Parameters @{ Expected = $cli } {
                param($Expected)
                Get-FancyZonesCliPath | Should -Be $Expected
            }
        }
        finally { $env:LOCALAPPDATA = $savedLocalAppData }
    }

    It "starts PowerToys in the background and waits until FancyZones is ready" {
        InModuleScope SystemSetup -Parameters @{ Root = $TestDrive } {
            param($Root)
            $powerToys = Join-Path $Root 'PowerToys.exe'
            [IO.File]::WriteAllText($powerToys, 'fixture; never executed')
            $script:fixtureProcessChecks = 0
            Mock Get-Process {
                if ($Name -eq 'PowerToys.FancyZones') {
                    $script:fixtureProcessChecks++
                    if ($script:fixtureProcessChecks -ge 3) { return [pscustomobject] @{ ProcessName = $Name } }
                }
            }
            Mock Start-Process {}
            Mock Start-Sleep {}
            Start-FancyZonesForSetup -CliPath (Join-Path $Root 'bin\PowerToys.FancyZones.CLI.exe')
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq $powerToys -and $WindowStyle -eq 'Hidden' }
            Should -Invoke Start-Sleep -Times 1 -Exactly
        }
    }

    It "bounds the wait when PowerToys is running with FancyZones disabled" {
        InModuleScope SystemSetup {
            Mock Get-Process {
                if ($Name -eq 'PowerToys') { return [pscustomobject] @{ ProcessName = $Name } }
            }
            Mock Start-Process {}
            Mock Start-Sleep {}
            { Start-FancyZonesForSetup -CliPath 'C:\fixture\bin\PowerToys.FancyZones.CLI.exe' } | Should -Throw '*Enable FancyZones*'
            Should -Invoke Start-Process -Times 0 -Exactly
            Should -Invoke Start-Sleep -Times 20 -Exactly
        }
    }
}
