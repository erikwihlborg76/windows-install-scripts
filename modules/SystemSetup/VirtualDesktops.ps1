function Get-VirtualDesktopTool {
    param(
        [Parameter()]
        [string] $ToolsRoot = (Join-Path $env:LOCALAPPDATA "WindowsInstallScripts\Tools\VirtualDesktop\1.21")
    )

    $windows = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
    $build = [int] $windows.CurrentBuildNumber
    if ($build -ge 26100) {
        $fileName = "VirtualDesktop11-24H2.exe"
        $expectedHash = "8334B529D19E71662950821C91ED996A0E92DF41C8D0A077E95151AA7041CB35"
    }
    elseif ($build -ge 22000) {
        $fileName = "VirtualDesktop11.exe"
        $expectedHash = "F6532DB79F6F0E4018CE77F08805D3FD3F7BB076CBFBAC0AC8189FE5376D9E82"
    }
    elseif ($windows.InstallationType -ne "Client" -and $build -eq 20348) {
        $fileName = "VirtualDesktopServer2022.exe"
        $expectedHash = "D7D0D508B0E049DC0B08191AD50BF876B71724DF57ECBF5575675BF6E7B04747"
    }
    elseif ($windows.InstallationType -eq "Client" -and $build -ge 19041) {
        $fileName = "VirtualDesktop.exe"
        $expectedHash = "1B05D47C393BFED4453112672CBAF852F803BFEDFB9BBA2840D2ABADA1995C7E"
    }
    else {
        throw "Named virtual desktops require Windows 10 2004 or later, Windows 11, or a supported desktop Windows Server installation (build $build)."
    }

    $executable = Join-Path $ToolsRoot $fileName
    if ((Test-Path -LiteralPath $executable -PathType Leaf) -and
        (Get-FileHash -LiteralPath $executable -Algorithm SHA256 -ErrorAction Stop).Hash -eq $expectedHash) {
        return $executable
    }

    New-Item -ItemType Directory -Path $ToolsRoot -Force -ErrorAction Stop | Out-Null
    $download = Join-Path $ToolsRoot ("download-" + [guid]::NewGuid().ToString("N") + ".tmp")
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $uri = "https://github.com/MScholtes/VirtualDesktop/releases/download/V1.21/$fileName"
        Invoke-WebRequest -Uri $uri -OutFile $download -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256 -ErrorAction Stop).Hash -ne $expectedHash) {
            throw "VirtualDesktop CLI SHA-256 mismatch: '$fileName'."
        }
        Move-Item -LiteralPath $download -Destination $executable -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $download -PathType Leaf) {
            Remove-Item -LiteralPath $download -Force -ErrorAction Stop
        }
    }
    return $executable
}

function Set-ConfiguredVirtualDesktops {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("HOME", "WORK")]
        [string] $Profile,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Names
    )

    if ($Profile -ne "WORK" -or $Names.Count -eq 0) {
        return
    }

    try {
        $executable = Get-VirtualDesktopTool
        $count = Invoke-SetupNativeCommand -FilePath $executable -Arguments @("/Quiet", "/Count")
        # This CLI returns desktop counts and indices as successful exit codes.
        if ($count.ExitCode -lt 1) {
            throw "Could not enumerate desktops (exit $($count.ExitCode)): $($count.Output -join ' ')"
        }
        $existingCount = $count.ExitCode
        for ($index = 0; $index -lt $Names.Count; $index++) {
            $selection = if ($index -lt $existingCount) { "/GetDesktop:$index" } else { "/New" }
            $result = Invoke-SetupNativeCommand -FilePath $executable -Arguments @(
                "/Quiet", $selection, "/Name:$($Names[$index])"
            )
            if ($result.ExitCode -ne $index) {
                throw "Could not configure desktop '$($Names[$index])' (exit $($result.ExitCode)): $($result.Output -join ' ')"
            }
        }
        Write-Host "[OK] WORK virtual desktops: $($Names -join ', '). Existing extra desktops were preserved."
    }
    catch {
        Write-Warning "Failed to configure WORK virtual desktops: $($_.Exception.Message)"
    }
}
