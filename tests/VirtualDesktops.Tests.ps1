BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psd1") -Force
}

Describe "Profile virtual desktops" {
    BeforeEach {
        Mock Get-VirtualDesktopTool -ModuleName SystemSetup { "fixture-virtualdesktop.exe" }
        Mock Write-Warning -ModuleName SystemSetup {}
    }

    It "creates only missing WORK desktops, keeps their order, and adds nothing on rerun" {
        InModuleScope SystemSetup {
            $script:fixtureDesktopNames = [Collections.Generic.List[string]]::new()
            $script:fixtureDesktopNames.Add("Desktop 1")
            Mock Invoke-SetupNativeCommand {
                if ($Arguments -contains "/Count") {
                    return [pscustomobject] @{ ExitCode = $script:fixtureDesktopNames.Count; Output = @() }
                }
                $name = @($Arguments | Where-Object { $_ -like '/Name:*' })[0].Substring(6)
                if ($Arguments -contains "/New") {
                    $index = $script:fixtureDesktopNames.Count
                    $script:fixtureDesktopNames.Add($name)
                }
                else {
                    $index = [int] (@($Arguments | Where-Object { $_ -like '/GetDesktop:*' })[0].Substring(12))
                    $script:fixtureDesktopNames[$index] = $name
                }
                return [pscustomobject] @{ ExitCode = $index; Output = @() }
            }

            Set-ConfiguredVirtualDesktops -Profile WORK -Names @("Plan", "Work", "Meet", "Play")
            Set-ConfiguredVirtualDesktops -Profile WORK -Names @("Plan", "Work", "Meet", "Play")

            @($script:fixtureDesktopNames) | Should -Be @("Plan", "Work", "Meet", "Play")
            Should -Invoke Invoke-SetupNativeCommand -Times 3 -Exactly -ParameterFilter { $Arguments -contains '/New' }
            Should -Invoke Write-Warning -Times 0 -Exactly
        }
    }

    It "reuses existing desktops and preserves any extra desktop" {
        InModuleScope SystemSetup {
            Mock Invoke-SetupNativeCommand {
                if ($Arguments -contains "/Count") {
                    return [pscustomobject] @{ ExitCode = 5; Output = @() }
                }
                $index = [int] (@($Arguments | Where-Object { $_ -like '/GetDesktop:*' })[0].Substring(12))
                return [pscustomobject] @{ ExitCode = $index; Output = @() }
            }

            Set-ConfiguredVirtualDesktops -Profile WORK -Names @("Plan", "Work", "Meet", "Play")

            Should -Invoke Invoke-SetupNativeCommand -Times 5 -Exactly
            Should -Invoke Invoke-SetupNativeCommand -Times 0 -Exactly -ParameterFilter {
                $Arguments -contains '/New' -or $Arguments -contains '/GetDesktop:4' -or
                @($Arguments | Where-Object { $_ -match '^/(Remove|Switch)' }).Count -gt 0
            }
            Should -Invoke Write-Warning -Times 0 -Exactly
        }
    }

    It "does not download tools or touch desktops for HOME even if names are supplied" {
        InModuleScope SystemSetup {
            Mock Invoke-SetupNativeCommand { throw "Must not run" }
            Set-ConfiguredVirtualDesktops -Profile HOME -Names @("Plan", "Work", "Meet", "Play")
            Should -Invoke Get-VirtualDesktopTool -Times 0 -Exactly
            Should -Invoke Invoke-SetupNativeCommand -Times 0 -Exactly
        }
    }

    It "reports an incompatible shell without attempting desktop changes" {
        InModuleScope SystemSetup {
            Mock Invoke-SetupNativeCommand {
                [pscustomobject] @{ ExitCode = -1; Output = @("Unsupported shell API") }
            }
            Set-ConfiguredVirtualDesktops -Profile WORK -Names @("Plan", "Work", "Meet", "Play")
            Should -Invoke Invoke-SetupNativeCommand -Times 1 -Exactly
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*Unsupported shell API*' }
        }
    }
}

Describe "Pinned virtual desktop CLI" {
    It "selects the cached executable for build <Build> (<Edition>) and checks its hash" -TestCases @(
        @{ Build = 19045; Edition = "Client"; File = "VirtualDesktop.exe"; Hash = "1B05D47C393BFED4453112672CBAF852F803BFEDFB9BBA2840D2ABADA1995C7E" }
        @{ Build = 22631; Edition = "Client"; File = "VirtualDesktop11.exe"; Hash = "F6532DB79F6F0E4018CE77F08805D3FD3F7BB076CBFBAC0AC8189FE5376D9E82" }
        @{ Build = 26100; Edition = "Client"; File = "VirtualDesktop11-24H2.exe"; Hash = "8334B529D19E71662950821C91ED996A0E92DF41C8D0A077E95151AA7041CB35" }
        @{ Build = 20348; Edition = "Server"; File = "VirtualDesktopServer2022.exe"; Hash = "D7D0D508B0E049DC0B08191AD50BF876B71724DF57ECBF5575675BF6E7B04747" }
        @{ Build = 26100; Edition = "Server"; File = "VirtualDesktop11-24H2.exe"; Hash = "8334B529D19E71662950821C91ED996A0E92DF41C8D0A077E95151AA7041CB35" }
    ) {
        param($Build, $Edition, $File, $Hash)
        InModuleScope SystemSetup -Parameters @{ Build = $Build; Edition = $Edition; File = $File; Hash = $Hash; Root = $TestDrive } {
            param($Build, $Edition, $File, $Hash, $Root)
            $script:fixtureBuild = $Build
            $script:fixtureEdition = $Edition
            $script:fixtureHash = $Hash
            $cached = Join-Path $Root $File
            [IO.File]::WriteAllText($cached, "fixture; never executed")
            Mock Get-ItemProperty { [pscustomobject] @{ CurrentBuildNumber = $script:fixtureBuild; InstallationType = $script:fixtureEdition } }
            Mock Get-FileHash { [pscustomobject] @{ Hash = $script:fixtureHash } }
            Mock Invoke-WebRequest { throw "Cache should be reused" }

            Get-VirtualDesktopTool -ToolsRoot $Root | Should -Be $cached

            Should -Invoke Get-FileHash -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $cached -and $Algorithm -eq 'SHA256' }
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }
    }

    It "rejects a corrupted download, preserves the old file, and cleans up the temporary download" {
        InModuleScope SystemSetup -Parameters @{ Root = $TestDrive } {
            param($Root)
            $tools = Join-Path $Root "bad-download"
            New-Item -ItemType Directory -Path $tools | Out-Null
            $cached = Join-Path $tools "VirtualDesktop11-24H2.exe"
            [IO.File]::WriteAllText($cached, 'existing file')
            Mock Get-ItemProperty { [pscustomobject] @{ CurrentBuildNumber = 26100; InstallationType = "Client" } }
            Mock Get-FileHash { [pscustomobject] @{ Hash = "INVALID" } }
            Mock Invoke-WebRequest { [IO.File]::WriteAllText($OutFile, 'invalid download') }

            { Get-VirtualDesktopTool -ToolsRoot $tools } | Should -Throw '*SHA-256 mismatch*'

            [IO.File]::ReadAllText($cached) | Should -BeExactly 'existing file'
            @(Get-ChildItem -LiteralPath $tools -Filter '*.tmp').Count | Should -Be 0
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://github.com/MScholtes/VirtualDesktop/releases/download/V1.21/VirtualDesktop11-24H2.exe'
            }
        }
    }
}
