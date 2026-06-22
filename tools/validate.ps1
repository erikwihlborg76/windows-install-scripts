[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$validationErrors = [System.Collections.Generic.List[string]]::new()
$approvedVerbs = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

Get-Verb | ForEach-Object {
    [void]$approvedVerbs.Add($_.Verb)
}

$requiredPaths = @(
    "00-run-install-manual.cmd"
    "00-install.ps1"
    "01-run-install-steps.ps1"
    "02-select-sync-root.ps1"
    "03-preconfigure-system.ps1"
    "04-install-apps.ps1"
    "05-postconfigure-system.ps1"
    "06-remove-apps.ps1"
    "settings\windows.ps1"
    "lib\admin.ps1"
    "lib\activation.ps1"
    "lib\app-removal.ps1"
    "lib\input.ps1"
    "lib\install-runner.ps1"
    "lib\links-and-copy.ps1"
    "lib\logging.ps1"
    "lib\sync-setup.ps1"
    "lib\system-info.ps1"
    "lib\apply-settings.ps1"
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
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $_.FullName,
            [ref] $tokens,
            [ref] $parseErrors
        )

        foreach ($parseError in $parseErrors) {
            $validationErrors.Add("$($_.FullName): $($parseError.Message)")
        }

        $functions = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)

        foreach ($function in $functions) {
            $verb = $function.Name.Split('-', 2)[0]
            if (-not $approvedVerbs.Contains($verb)) {
                $validationErrors.Add(
                    "$($_.FullName): function '$($function.Name)' uses non-approved verb '$verb'."
                )
            }
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

Write-Host "[OK] PowerShell syntax, function verbs, JSON files, and required repository files are valid."
