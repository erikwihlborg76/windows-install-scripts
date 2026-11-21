BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $configuration = Import-PowerShellDataFile `
        -LiteralPath (Join-Path $repositoryRoot "config\Profiles.psd1")
}

Describe "Profile intent" {
    It "keeps HOME and WORK differences in profile data" {
        $configuration.HOME.PromptForComputerName | Should -BeTrue
        $configuration.WORK.PromptForComputerName | Should -BeFalse
        @($configuration.HOME.VirtualDesktopNames).Count | Should -Be 0
        $configuration.WORK.VirtualDesktopNames | Should -Be @("Plan", "Work", "Meet", "Play")
        $configuration.WORK.AdditionalPackageManifests | Should -Contain "packages.work.json"
        $configuration.HOME.AdditionalWingetNameRemovals | Should -Contain "Microsoft Teams"
    }

    It "keeps the LGPO-owned AllowTelemetry policy out of registry configuration" {
        $settings = @($configuration.Common.Registry) +
            @($configuration.HOME.Registry) +
            @($configuration.WORK.Registry)
        @($settings | Where-Object { $_.Name -eq "AllowTelemetry" }) | Should -HaveCount 0
    }

    It "omits obsolete feeds, HomeGroup, and peer networking settings" {
        @($configuration.Common.Registry | Where-Object {
            $_.Name -in @("EnableFeeds", "DisableHomeGroup") -or $_.Path -like '*\Peernet'
        }) | Should -HaveCount 0
    }

    It "configures the complete Never feedback preference with documented DWORD values" {
        $feedback = @($configuration.Common.Registry | Where-Object Path -eq 'HKCU:\Software\Microsoft\Siuf\Rules')
        @($feedback.Name) | Should -Contain "NumberOfSIUFInPeriod"
        @($feedback.Name) | Should -Contain "PeriodInNanoSeconds"
        foreach ($setting in $feedback) {
            $setting.Type | Should -Be "DWord"
            $setting.Value | Should -Be 0
        }
    }

    It "applies the Alt+Tab policy only at its documented user scope" {
        $settings = @($configuration.Common.Registry | Where-Object Name -eq "MultiTaskingAltTabFilter")
        $settings | Should -HaveCount 1
        $settings[0].Path | Should -Be 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
        $settings[0].Value | Should -Be 4
    }

    It "does not create placeholder MDM enrollment or account provisioning records" {
        $settings = @($configuration.Common.Registry) + @($configuration.HOME.Registry) + @($configuration.WORK.Registry)
        @($settings | Where-Object {
            $_.Path -like '*\Microsoft\Enrollments\*' -or $_.Path -like '*\Microsoft\Provisioning\OMADM\Accounts\*'
        }) | Should -HaveCount 0
    }
}
