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
            @($configuration.Common.ApplicationRegistry) +
            @($configuration.HOME.Registry) +
            @($configuration.WORK.Registry)
        @($settings | Where-Object { $_.Name -eq "AllowTelemetry" }) | Should -HaveCount 0
    }
}
