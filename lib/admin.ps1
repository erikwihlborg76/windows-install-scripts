function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run this script as Administrator."
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-ScriptAsAdministrator {
    param(
        [Parameter(Mandatory)]
        [string] $ScriptPath
    )

    if (Test-Administrator) {
        return $false
    }

    $argumentList = @(
        "-NoLogo"
        "-NoProfile"
        "-ExecutionPolicy"
        "Bypass"
        "-File"
        "`"$ScriptPath`""
    ) -join " "

    Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList $argumentList `
        -Verb RunAs

    return $true
}
