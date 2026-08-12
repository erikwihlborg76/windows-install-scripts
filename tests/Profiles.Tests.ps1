$repositoryRoot = Split-Path -Parent $PSScriptRoot
$configuration = Import-PowerShellDataFile `
    -LiteralPath (Join-Path $repositoryRoot "config\Profiles.psd1")

Describe "Profile configuration" {
    It "defines common, HOME, and WORK sections" {
        foreach ($section in @("Common", "HOME", "WORK")) {
            if (-not $configuration.ContainsKey($section)) {
                throw "Missing profile configuration section: $section"
            }
        }
    }

    It "keeps HOME and WORK differences in profile data" {
        if (-not $configuration.HOME.PromptForComputerName) {
            throw "HOME should prompt for a computer name."
        }
        if ($configuration.WORK.PromptForComputerName) {
            throw "WORK should not prompt for a computer name."
        }
        if (-not $configuration.HOME.DisableLastAccess) {
            throw "HOME should disable last-access updates."
        }
        if ($configuration.WORK.DisableLastAccess) {
            throw "WORK should not disable last-access updates."
        }
        if ($configuration.WORK.AdditionalPackageManifests -notcontains "packages.work.json") {
            throw "WORK is missing its package manifest."
        }
        if ($configuration.HOME.AdditionalWingetNameRemovals -notcontains "Microsoft Teams") {
            throw "HOME is missing its Teams removal."
        }
    }

    It "does not duplicate the LGPO-owned AllowTelemetry policy" {
        $duplicates = @(
            $configuration.Common.Registry |
                Where-Object { $_.Name -eq "AllowTelemetry" }
        )
        if ($duplicates.Count -ne 0) {
            throw "AllowTelemetry is duplicated outside LGPO."
        }
    }

    It "defines complete typed registry settings" {
        $settings = @($configuration.Common.Registry) +
            @($configuration.HOME.Registry) +
            @($configuration.WORK.Registry)

        foreach ($setting in $settings) {
            foreach ($property in @("Path", "Name", "Type", "Value")) {
                if (-not $setting.ContainsKey($property)) {
                    throw "Registry setting is missing property: $property"
                }
            }
            if ($setting.Type -notin @(
                    "String",
                    "ExpandString",
                    "DWord",
                    "QWord",
                    "Binary",
                    "MultiString"
                )) {
                throw "Unsupported registry setting type: $($setting.Type)"
            }
        }
    }

    It "preserves the configured operation inventory" {
        $expectedCounts = @{
            CommonRegistry = 46
            HomeRegistry = 8
            Services = 4
            ScheduledTasks = 9
            AppxRemovals = 23
            WingetRemovals = 5
            Capabilities = 1
        }
        $actualCounts = @{
            CommonRegistry = @($configuration.Common.Registry).Count
            HomeRegistry = @($configuration.HOME.Registry).Count
            Services = @($configuration.Common.ServicesToDisable).Count
            ScheduledTasks = @($configuration.Common.ScheduledTasksToDisable).Count
            AppxRemovals = @($configuration.Common.AppxRemovals).Count
            WingetRemovals = @($configuration.Common.WingetNameRemovals).Count
            Capabilities = @($configuration.Common.CapabilitiesToRemove).Count
        }

        foreach ($name in $expectedCounts.Keys) {
            if ($actualCounts[$name] -ne $expectedCounts[$name]) {
                throw "Expected $($expectedCounts[$name]) $name entries; found $($actualCounts[$name])."
            }
        }
    }
}

Describe "WinGet package manifests" {
    It "contains package identifiers in every manifest" {
        $manifestPaths = Get-ChildItem `
            -LiteralPath (Join-Path $repositoryRoot "config") `
            -File `
            -Filter "packages.*.json"

        foreach ($manifestPath in $manifestPaths) {
            $manifest = Get-Content -LiteralPath $manifestPath.FullName -Raw |
                ConvertFrom-Json
            $packageIds = @(
                $manifest.Sources | ForEach-Object { $_.Packages.PackageIdentifier }
            )
            if ($packageIds.Count -eq 0) {
                throw "Package manifest is empty: $($manifestPath.FullName)"
            }
        }
    }

    It "preserves the common and WORK package sets" {
        $expectedPackages = @{
            "packages.common.json" = @(
                "AgileBits.1Password"
                "dotPDN.PaintDotNet"
                "Ghisler.TotalCommander"
                "Git.Git"
                "Highresolution.X-MouseButtonControl"
                "Microsoft.PowerShell"
                "Microsoft.PowerToys"
                "Microsoft.SecurityComplianceToolkit.LGPO"
                "Microsoft.VisualStudioCode"
                "Microsoft.WindowsTerminal"
                "Notion.Notion"
                "PeterPawlowski.foobar2000"
            )
            "packages.work.json" = @("OpenJS.NodeJS.LTS")
        }

        foreach ($manifestName in $expectedPackages.Keys) {
            $manifest = Get-Content `
                -LiteralPath (Join-Path $repositoryRoot "config\$manifestName") `
                -Raw |
                ConvertFrom-Json
            $actual = @(
                $manifest.Sources |
                    ForEach-Object { $_.Packages.PackageIdentifier } |
                    Sort-Object
            )
            $differences = @(
                Compare-Object `
                    -ReferenceObject ($expectedPackages[$manifestName] | Sort-Object) `
                    -DifferenceObject $actual
            )
            if ($differences.Count -ne 0) {
                throw "Package set changed in ${manifestName}: $($differences | Out-String)"
            }
        }
    }
}
