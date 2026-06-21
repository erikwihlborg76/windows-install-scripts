function Assert-WinGet {
    param(
        [Parameter()]
        [string] $Message = "winget was not found. Run the bootstrap/install script first, or install/update App Installer from Microsoft Store."
    )

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw $Message
    }
}

function Convert-WinGetExitCodeToErrorArgument {
    param(
        [Parameter(Mandatory)]
        [int] $ExitCode
    )

    if ($ExitCode -ge 0) {
        return $ExitCode.ToString()
    }

    $unsignedExitCode = [BitConverter]::ToUInt32([BitConverter]::GetBytes($ExitCode), 0)
    return ("0x{0:X8}" -f $unsignedExitCode)
}

function Get-WinGetReturnCodeInfo {
    param(
        [Parameter(Mandatory)]
        [int] $ExitCode
    )

    $knownReturnCodes = @{
        0 = [pscustomobject]@{
            Hex         = "0x00000000"
            Symbol      = "S_OK"
            Description = "Success"
        }
        -1978335189 = [pscustomobject]@{
            Hex         = "0x8A15002B"
            Symbol      = "APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE"
            Description = "No applicable update found"
        }
        -1978335135 = [pscustomobject]@{
            Hex         = "0x8A150061"
            Symbol      = "APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED"
            Description = "Found at least one version of the package installed"
        }
        -2143322111 = [pscustomobject]@{
            Hex         = "0x803F8001"
            Symbol      = "STORE_LICENSE_OR_AVAILABILITY_ERROR"
            Description = "Microsoft Store licensing or availability error"
        }
    }

    if ($knownReturnCodes.ContainsKey($ExitCode)) {
        return $knownReturnCodes[$ExitCode]
    }

    return [pscustomobject]@{
        Hex         = Convert-WinGetExitCodeToErrorArgument -ExitCode $ExitCode
        Symbol      = "UNKNOWN"
        Description = "Unknown WinGet or installer return code"
    }
}

function Test-WinGetInstallSuccessExitCode {
    param(
        [Parameter(Mandatory)]
        [int] $ExitCode
    )

    return ($ExitCode -in @(
            # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE: No applicable update found.
            -1978335189,

            # APPINSTALLER_CLI_ERROR_PACKAGE_ALREADY_INSTALLED: Found at least one version installed.
            -1978335135
        ))
}

function Install-Pkg {
    param(
        [Parameter(Mandatory)]
        [string] $Id,

        [Parameter(Mandatory)]
        [ValidateSet("winget", "msstore")]
        [string] $Source,

        [Parameter()]
        [string] $Name = $Id,

        [Parameter()]
        [switch] $Optional
    )

    if ([string]::IsNullOrWhiteSpace($Id)) {
        Write-Host "[WARN] Empty package id. Skipping."
        return
    }

    if ([string]::IsNullOrWhiteSpace($Source)) {
        Write-Host "[WARN] Empty source for `"$Id`". Skipping."
        return
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = $Id
    }

    Write-Host "[INSTALL] $Name ($Id)"

    Write-LogLine ""
    Write-LogLine "============================================================"
    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Name ($Id) from $Source"
    Write-LogLine "============================================================"

    $wingetArgs = @(
        "install"
        "--id", $Id
        "--source", $Source
        "--exact"
        "--silent"
        "--accept-package-agreements"
        "--accept-source-agreements"
    )

    $output = & winget @wingetArgs 2>&1
    $rc = $LASTEXITCODE

    foreach ($line in $output) {
        Write-LogLine $line.ToString()
    }

    if ($rc -ne 0) {
        $returnCodeInfo = Get-WinGetReturnCodeInfo -ExitCode $rc

        if (Test-WinGetInstallSuccessExitCode -ExitCode $rc) {
            Write-Host "[OK] Installed or already available: $Name"
            Write-LogLine "[OK] Winget returned $($returnCodeInfo.Symbol) ($($returnCodeInfo.Hex), $rc): $($returnCodeInfo.Description)."
            return
        }

        Write-Host "[WARN] Install failed: $Name ($Id), exit code $rc"
        Write-Host "  $($returnCodeInfo.Hex) $($returnCodeInfo.Symbol): $($returnCodeInfo.Description)"
        Write-LogLine "[WARN] Install failed with $($returnCodeInfo.Symbol) ($($returnCodeInfo.Hex), $rc): $($returnCodeInfo.Description)"

        $errorArgument = Convert-WinGetExitCodeToErrorArgument -ExitCode $rc
        $errorOutput = & winget error $errorArgument 2>&1
        foreach ($line in $errorOutput) {
            $message = $line.ToString()
            Write-Host "  $message"
            Write-LogLine $message
        }

        if ($Optional) {
            Write-Host "[WARN] Optional package failed and will not fail the install summary: $Name"
            Write-LogLine "[WARN] Optional package failure ignored."
            return
        }

        $script:FailedCount++
    }
    else {
        Write-Host "[OK] Installed or already available: $Name"
        Write-LogLine "[OK] Install completed."
    }
}

function Invoke-WinGetErrorLookup {
    param(
        [Parameter(Mandatory)]
        [int] $ExitCode
    )

    try {
        $errorArgument = Convert-WinGetExitCodeToErrorArgument -ExitCode $ExitCode
        & winget error $errorArgument 1>> $script:Log 2>&1
    }
    catch {
        Write-LogLine "[WARN] Could not run winget error $ExitCode. $($_.Exception.Message)"
    }
}
