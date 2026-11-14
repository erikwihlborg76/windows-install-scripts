[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$validationErrors = [Collections.Generic.List[string]]::new()
$approvedVerbs = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase
)

Get-Verb | ForEach-Object { [void] $approvedVerbs.Add($_.Verb) }

$requiredPaths = @(
    "00-install.ps1"
    "00-run-install-manual.cmd"
    "Install.ps1"
    "config\Profiles.psd1"
    "modules\SystemSetup\SystemSetup.psd1"
    "modules\SystemSetup\SystemSetup.psm1"
    "modules\SystemSetup\ApplicationSettings.ps1"
    "modules\SystemSetup\VirtualDesktops.ps1"
    "modules\SystemSetup\FancyZonesSettings.ps1"
    "modules\SystemSetup\TerminalSettings.ps1"
    "modules\SyncProfile\SyncProfile.psd1"
    "modules\SyncProfile\SyncProfile.psm1"
    "resources\LGPO\global_policy_objects.txt"
    "resources\Windows Terminal\settings.json"
    "resources\X-Mouse Button Control\XMBCSettings.xml"
    "resources\PowerToys\FancyZones\settings.json"
    "resources\PowerToys\FancyZones\custom-layouts.json"
    "resources\PowerToys\LightSwitch\settings.json"
    "resources\PowerToys\CommandPalette\settings.json"
    "resources\foobar2000-v2\config.sqlite"
    "resources\foobar2000-v2\theme.fth"
    "resources\foobar2000-v2\playlists-v2.0\index.txt"
    "resources\foobar2000-v2\playlists-v2.0\playlist-8CD72BCC-0298-48EE-88C9-2783441A585F.fplite"
    "resources\foobar2000-v2\playlists-v2.0\playlist-8CD72BCC-0298-48EE-88C9-2783441A585F-props.sqlite"
    "tests\Architecture.Tests.ps1"
    "tests\Profiles.Tests.ps1"
    "tests\SyncProfile.Tests.ps1"
    "tests\SystemSetup.Tests.ps1"
    "tests\ApplicationSettings.Tests.ps1"
    "tests\VirtualDesktops.Tests.ps1"
    "tests\FancyZones.Tests.ps1"
    "tests\TerminalSettings.Tests.ps1"
)

foreach ($relativePath in $requiredPaths) {
    $fullPath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $validationErrors.Add("Missing required file: $relativePath")
    }
}

$powerShellFiles = Get-ChildItem `
    -LiteralPath $repositoryRoot `
    -Recurse `
    -File |
    Where-Object { $_.Extension -in @(".ps1", ".psm1") }

foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref] $tokens,
        [ref] $parseErrors
    )

    foreach ($parseError in $parseErrors) {
        $validationErrors.Add("$($file.FullName): $($parseError.Message)")
    }

    $functions = $ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst]
    }, $true)

    foreach ($function in $functions) {
        $verb = $function.Name.Split('-', 2)[0]
        if (-not $approvedVerbs.Contains($verb)) {
            $validationErrors.Add(
                "$($file.FullName): function '$($function.Name)' uses non-approved verb '$verb'."
            )
        }
    }
}

Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File -Filter "*.json" |
    ForEach-Object {
        try {
            $json = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            if ($_.DirectoryName -eq (Join-Path $repositoryRoot "config")) {
                $manifestPath = $_.FullName
                $packages = @($json.Sources | ForEach-Object { $_.Packages })
                if ($packages.Count -eq 0) {
                    $validationErrors.Add("WinGet manifest contains no packages: $($_.FullName)")
                }
                $packageIds = [Collections.Generic.HashSet[string]]::new(
                    [StringComparer]::OrdinalIgnoreCase
                )
                foreach ($package in $packages) {
                    if ([string]::IsNullOrWhiteSpace($package.PackageIdentifier)) {
                        $validationErrors.Add("PackageIdentifier must be nonempty: $manifestPath")
                    }
                    elseif (-not $packageIds.Add($package.PackageIdentifier)) {
                        $validationErrors.Add("Duplicate package '$($package.PackageIdentifier)': $manifestPath")
                    }
                }
            }
        }
        catch {
            $validationErrors.Add("$($_.FullName): $($_.Exception.Message)")
        }
    }

try {
    $profiles = Import-PowerShellDataFile `
        -LiteralPath (Join-Path $repositoryRoot "config\Profiles.psd1")

    $requiredProperties = @{
        Common = @(
            "PackageManifest", "Registry", "ApplicationRegistry", "ServicesToDisable", "ScheduledTasksToDisable",
            "AppxRemovals", "WingetNameRemovals", "CapabilitiesToRemove"
        )
        HOME = @(
            "BootLabel", "PromptForComputerName", "VirtualDesktopNames",
            "AdditionalPackageManifests", "AdditionalWingetNameRemovals", "Registry"
        )
    }
    $requiredProperties.WORK = $requiredProperties.HOME

    foreach ($profileName in @("Common", "HOME", "WORK")) {
        if ($profiles[$profileName] -isnot [Collections.IDictionary]) {
            $validationErrors.Add("Profiles.psd1 requires a hashtable section: $profileName")
            continue
        }
        foreach ($requiredProperty in $requiredProperties[$profileName]) {
            if (-not $profiles[$profileName].ContainsKey($requiredProperty)) {
                $validationErrors.Add("Profile $profileName is missing property: $requiredProperty")
            }
        }
    }

    foreach ($profileName in @("HOME", "WORK")) {
        $profile = $profiles[$profileName]
        if ($profile -isnot [Collections.IDictionary]) {
            continue
        }
        if ([string]::IsNullOrWhiteSpace($profile.BootLabel)) {
            $validationErrors.Add("Profile $profileName requires a nonempty BootLabel.")
        }
        if ($profile.PromptForComputerName -isnot [bool]) {
            $validationErrors.Add("Profile $profileName requires a Boolean PromptForComputerName.")
        }
        if ($profile.VirtualDesktopNames -isnot [array]) {
            $validationErrors.Add("Profile $profileName requires a VirtualDesktopNames array.")
        }
        else {
            $desktopNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($desktopName in $profile.VirtualDesktopNames) {
                if ($desktopName -isnot [string] -or [string]::IsNullOrWhiteSpace($desktopName)) {
                    $validationErrors.Add("Profile $profileName requires nonempty virtual desktop names.")
                }
                elseif (-not $desktopNames.Add($desktopName)) {
                    $validationErrors.Add("Profile $profileName has a duplicate virtual desktop name: $desktopName")
                }
            }
        }
    }

    $manifestNames = @($profiles.Common.PackageManifest) +
        @($profiles.HOME.AdditionalPackageManifests) +
        @($profiles.WORK.AdditionalPackageManifests)
    foreach ($manifestName in $manifestNames) {
        if ([string]::IsNullOrWhiteSpace($manifestName)) {
            $validationErrors.Add("Package manifest references must be nonempty.")
        }
        elseif (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot "config\$manifestName") -PathType Leaf)) {
            $validationErrors.Add("Referenced package manifest was not found: $manifestName")
        }
    }

    $registrySettings = @($profiles.Common.Registry) +
        @($profiles.Common.ApplicationRegistry) +
        @($profiles.HOME.Registry) +
        @($profiles.WORK.Registry)

    foreach ($setting in $registrySettings) {
        if ($setting -isnot [Collections.IDictionary]) {
            $validationErrors.Add("Registry settings must be hashtables.")
            continue
        }
        foreach ($property in @("Path", "Name", "Type", "Value")) {
            if (-not $setting.ContainsKey($property)) {
                $validationErrors.Add("Registry setting is missing property '$property': $setting")
            }
        }

        if ($setting.Type -notin @("String", "ExpandString", "DWord", "QWord", "Binary", "MultiString")) {
            $validationErrors.Add("Unsupported registry value type: $($setting.Type)")
        }
        if ([string]::IsNullOrWhiteSpace($setting.Path)) {
            $validationErrors.Add("Registry setting requires a nonempty Path.")
        }
    }
}
catch {
    $validationErrors.Add("Could not validate Profiles.psd1: $($_.Exception.Message)")
}

foreach ($moduleManifest in @(
        "modules\SystemSetup\SystemSetup.psd1",
        "modules\SyncProfile\SyncProfile.psd1"
    )) {
    try {
        Test-ModuleManifest `
            -Path (Join-Path $repositoryRoot $moduleManifest) `
            -ErrorAction Stop |
            Out-Null
    }
    catch {
        $validationErrors.Add("Invalid module manifest '$moduleManifest': $($_.Exception.Message)")
    }
}

if ($validationErrors.Count -gt 0) {
    foreach ($validationError in $validationErrors) {
        Write-Host "[ERROR] $validationError"
    }
    throw "Repository validation failed with $($validationErrors.Count) error(s)."
}

Write-Host "[OK] Syntax, verbs, manifests, configuration data, and required files are valid."
