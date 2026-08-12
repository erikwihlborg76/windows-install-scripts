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
    "config\packages.common.json"
    "config\packages.work.json"
    "modules\SystemSetup\SystemSetup.psd1"
    "modules\SystemSetup\SystemSetup.psm1"
    "modules\SyncProfile\SyncProfile.psd1"
    "modules\SyncProfile\SyncProfile.psm1"
    "resources\LGPO\global_policy_objects.txt"
    "resources\Windows Terminal\settings.json"
    "tests\Architecture.Tests.ps1"
    "tests\Profiles.Tests.ps1"
    "tests\SyncProfile.Tests.ps1"
    "tests\SystemSetup.Tests.ps1"
)

foreach ($relativePath in $requiredPaths) {
    $fullPath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $validationErrors.Add("Missing required file: $relativePath")
    }
}

$obsoletePaths = @(
    "01-run-install-steps.ps1"
    "02-select-sync-root.ps1"
    "03-preconfigure-system.ps1"
    "04-install-apps.ps1"
    "05-postconfigure-system.ps1"
    "06-apply-system-tweaks.ps1"
    "07-remove-apps.ps1"
    "lib"
    "settings"
)

foreach ($relativePath in $obsoletePaths) {
    if (Test-Path -LiteralPath (Join-Path $repositoryRoot $relativePath)) {
        $validationErrors.Add("Obsolete execution layer still exists: $relativePath")
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
                $packageIds = @(
                    $json.Sources | ForEach-Object { $_.Packages.PackageIdentifier }
                )
                if ($packageIds.Count -eq 0) {
                    $validationErrors.Add("WinGet manifest contains no packages: $($_.FullName)")
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

    foreach ($requiredSection in @("Common", "HOME", "WORK")) {
        if (-not $profiles.ContainsKey($requiredSection)) {
            $validationErrors.Add("Profiles.psd1 is missing section: $requiredSection")
        }
    }

    foreach ($profileName in @("HOME", "WORK")) {
        foreach ($requiredProperty in @(
                "BootLabel",
                "PromptForComputerName",
                "DisableLastAccess",
                "AdditionalPackageManifests",
                "AdditionalWingetNameRemovals",
                "Registry"
            )) {
            if (-not $profiles[$profileName].ContainsKey($requiredProperty)) {
                $validationErrors.Add("Profile $profileName is missing property: $requiredProperty")
            }
        }
    }

    $registrySettings = @($profiles.Common.Registry) +
        @($profiles.HOME.Registry) +
        @($profiles.WORK.Registry)

    foreach ($setting in $registrySettings) {
        foreach ($property in @("Path", "Name", "Type", "Value")) {
            if (-not $setting.ContainsKey($property)) {
                $validationErrors.Add("Registry setting is missing property '$property': $setting")
            }
        }

        if ($setting.Type -notin @("String", "ExpandString", "DWord", "QWord", "Binary", "MultiString")) {
            $validationErrors.Add("Unsupported registry value type: $($setting.Type)")
        }
    }
}
catch {
    $validationErrors.Add("Could not import Profiles.psd1: $($_.Exception.Message)")
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

$systemModulePath = Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psm1"
if (Test-Path -LiteralPath $systemModulePath -PathType Leaf) {
    $systemModuleText = Get-Content -LiteralPath $systemModulePath -Raw
    foreach ($forbiddenPattern in @(
            '\$SyncRoot',
            'Apps-data',
            'OneDrive',
            'Dropbox'
        )) {
        if ($systemModuleText -match $forbiddenPattern) {
            $validationErrors.Add(
                "SystemSetup contains sync-specific dependency matching: $forbiddenPattern"
            )
        }
    }
}

$productionPowerShellFiles = @(
    Get-Item -LiteralPath (Join-Path $repositoryRoot "00-install.ps1")
    Get-Item -LiteralPath (Join-Path $repositoryRoot "Install.ps1")
    Get-ChildItem `
        -LiteralPath (Join-Path $repositoryRoot "modules") `
        -Recurse `
        -File |
        Where-Object { $_.Extension -in @(".ps1", ".psm1") }
)

$allPowerShellText = ($productionPowerShellFiles |
        ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"

foreach ($obsoletePattern in @(
        'Invoke-InstallStep',
        '\$script:Log',
        '\$script:FailedCount',
        'reg\.exe\s+add',
        'schtasks\.exe',
        'sc\.exe\s+(query|config)',
        'dism\.exe'
    )) {
    if ($allPowerShellText -match $obsoletePattern) {
        $validationErrors.Add("Obsolete wrapper/native pattern remains: $obsoletePattern")
    }
}

if ($validationErrors.Count -gt 0) {
    foreach ($validationError in $validationErrors) {
        Write-Host "[ERROR] $validationError"
    }
    throw "Repository validation failed with $($validationErrors.Count) error(s)."
}

Write-Host "[OK] Syntax, verbs, manifests, configuration data, architecture boundaries, and required files are valid."
