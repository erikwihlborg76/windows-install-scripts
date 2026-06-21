function Initialize-InstallLog {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $StartMessage
    )

    $script:Log = $Path
    $script:FailedCount = 0
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $StartMessage" |
        Set-Content -LiteralPath $script:Log
}

function Get-InstallWarningCount {
    return $script:FailedCount
}

function Write-LogLine {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message
    )

    if ([string]::IsNullOrWhiteSpace($script:Log)) {
        throw "Install logging has not been initialized."
    }

    Add-Content -LiteralPath $script:Log -Value $Message
}

function Write-Ok {
    param(
        [Parameter(Mandatory)]
        [string] $Message
    )

    Write-Host "[OK] $Message"
    Write-LogLine "[OK] $Message"
}

function Write-Info {
    param(
        [Parameter(Mandatory)]
        [string] $Message
    )

    Write-Host "[INFO] $Message"
    Write-LogLine "[INFO] $Message"
}

function Write-Warn {
    param(
        [Parameter(Mandatory)]
        [string] $Message
    )

    Write-Host "[WARN] $Message"
    Write-LogLine "[WARN] $Message"
    $script:FailedCount++
}
