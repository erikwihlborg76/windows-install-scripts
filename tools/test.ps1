[CmdletBinding()]
param(
    [string] $PesterModulePath,
    [string] $ScriptAnalyzerModulePath
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot

$dependencies = @(
    @{ Name = "Pester"; Version = [version] "5.7.1"; Path = $PesterModulePath }
    @{ Name = "PSScriptAnalyzer"; Version = [version] "1.25.0"; Path = $ScriptAnalyzerModulePath }
)

foreach ($dependency in $dependencies) {
    $import = @{ Name = $dependency.Name; RequiredVersion = $dependency.Version }
    if ($dependency.Path) {
        $import = @{ Name = $dependency.Path }
    }
    try {
        $module = Import-Module @import -Force -PassThru -ErrorAction Stop
        if ($module.Version -ne $dependency.Version) {
            throw "Loaded version $($module.Version); expected $($dependency.Version)."
        }
    }
    catch {
        throw "Load $($dependency.Name) $($dependency.Version) before testing. Install-Module $($dependency.Name) -RequiredVersion $($dependency.Version) -Scope CurrentUser. $($_.Exception.Message)"
    }
}

& (Join-Path $PSScriptRoot "validate.ps1")

$issues = @(Invoke-ScriptAnalyzer -Path $repositoryRoot -Recurse -Severity Error)
if ($issues.Count -gt 0) {
    $issues | Format-Table -AutoSize
    throw "PSScriptAnalyzer found $($issues.Count) error(s)."
}

$testResult = Invoke-Pester -Path (Join-Path $repositoryRoot "tests") -PassThru
if ($testResult.Result -ne "Passed" -or $testResult.TotalCount -eq 0) {
    throw "Pester did not pass: $($testResult.Result), $($testResult.FailedCount) failed test(s)."
}
