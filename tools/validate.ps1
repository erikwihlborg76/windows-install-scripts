[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$validationErrors = [System.Collections.Generic.List[string]]::new()

$requiredPaths = @(
    "00-run-install.cmd"
    "install.ps1"
    "01-run-install-steps.ps1"
    "02-select-sync-root.ps1"
    "03-preconfigure-system.ps1"
    "04-install-apps.ps1"
    "05-postconfigure-system.ps1"
    "06-remove-bloatware.ps1"
    "lib\admin.ps1"
    "lib\activation.ps1"
    "lib\app-removal.ps1"
    "lib\input.ps1"
    "lib\install-runner.ps1"
    "lib\links-and-copy.ps1"
    "lib\logging.ps1"
    "lib\sync-setup.ps1"
    "lib\system-info.ps1"
    "lib\system-tweaks.ps1"
    "lib\winget.ps1"
    "resources\LGPO\global_policy_objects.txt"
    "resources\Windows Terminal\settings.json"
)

foreach ($relativePath in $requiredPaths) {
    $fullPath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $validationErrors.Add("Missing required file: $relativePath")
    }
}

Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File -Filter "*.ps1" |
    ForEach-Object {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $_.FullName,
            [ref] $tokens,
            [ref] $parseErrors
        )

        foreach ($parseError in $parseErrors) {
            $validationErrors.Add("$($_.FullName): $($parseError.Message)")
        }
    }

Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File -Filter "*.json" |
    ForEach-Object {
        try {
            Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null
        }
        catch {
            $validationErrors.Add("$($_.FullName): $($_.Exception.Message)")
        }
    }

if ($validationErrors.Count -gt 0) {
    foreach ($validationError in $validationErrors) {
        Write-Host "[ERROR] $validationError"
    }
    throw "Repository validation failed with $($validationErrors.Count) error(s)."
}

Write-Host "[OK] PowerShell syntax, JSON files, and required repository files are valid."
