function Invoke-InstallStep {
    param(
        [Parameter(Mandatory)]
        [string] $Step,

        [Parameter(Mandatory)]
        [string] $ScriptRoot,

        [Parameter()]
        [System.Collections.IDictionary] $Parameters = @{}
    )

    $scriptPath = Join-Path $scriptRoot $Step
    $scriptName = Split-Path -Leaf $scriptPath
    $scriptExt = [System.IO.Path]::GetExtension($scriptPath)

    Write-Host ""
    Write-Host "Running: $scriptName"

    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Missing install step: $scriptPath"
    }

    if ($scriptExt -ine ".ps1") {
        throw "Unsupported install step type '$scriptExt': $scriptPath"
    }

    $argumentList = @(
        "-NoLogo"
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", $scriptPath
    )

    foreach ($parameter in ($Parameters.GetEnumerator() | Sort-Object Key)) {
        $argumentList += "-$($parameter.Key)"
        $argumentList += [string] $parameter.Value
    }

    & powershell.exe @argumentList
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw "Step failed: $scriptName. Exit code: $exitCode"
    }

    Write-Host "[OK] Step completed: $scriptName"
}
