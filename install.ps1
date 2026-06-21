# Public bootstrap entry point.
# After publishing, run with:
#   irm https://raw.githubusercontent.com/erikwihlborg76/windows-install-scripts/main/install.ps1 | iex

& {
    $ErrorActionPreference = "Stop"

    # Set these environment variables only when testing a fork or a non-main ref.
    $repository = if ($env:INSTALL_REPOSITORY) { $env:INSTALL_REPOSITORY } else { "erikwihlborg76/windows-install-scripts" }
    $ref = if ($env:INSTALL_REF) { $env:INSTALL_REF } else { "main" }
    $expectedHash = $env:INSTALL_ARCHIVE_SHA256

    if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage") {
        throw "PowerShell must be running in Full Language Mode."
    }

    try {
        [void][System.AppDomain]::CurrentDomain.GetAssemblies()
        [void][System.Math]::Sqrt(144)
    }
    catch {
        throw "PowerShell could not load the required .NET APIs: $($_.Exception.Message)"
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    catch {
        # Modern PowerShell already negotiates TLS correctly.
    }

    $runId = [Guid]::NewGuid().Guid
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $tempRoot = Join-Path $tempBase "Install-$runId"
    $archivePath = Join-Path $tempRoot "repository.zip"
    $extractPath = Join-Path $tempRoot "repository"
    $archiveUrl = "https://codeload.github.com/$repository/zip/$ref"

    try {
        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

        Write-Progress -Activity "Downloading installer" -Status $repository
        Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath -UseBasicParsing
        Write-Progress -Activity "Downloading installer" -Completed

        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            throw "GitHub did not create the installer archive."
        }

        if ((Get-Item -LiteralPath $archivePath).Length -lt 1024) {
            throw "The downloaded installer archive is unexpectedly small."
        }

        if ($expectedHash) {
            $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
            if ($actualHash -ne $expectedHash) {
                throw "Installer archive SHA-256 mismatch. Expected $expectedHash; received $actualHash."
            }
        }

        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force

        $launchers = @(Get-ChildItem -LiteralPath $extractPath -Filter "00-run-install.cmd" -File -Recurse)
        if ($launchers.Count -ne 1) {
            throw "Expected exactly one 00-run-install.cmd in the downloaded repository; found $($launchers.Count)."
        }

        $launcher = $launchers[0].FullName
        $installerRoot = Split-Path -Parent $launcher
        foreach ($requiredFile in @("01-run-install-steps.ps1", "02-select-sync-root.ps1")) {
            $requiredPath = Join-Path $installerRoot $requiredFile
            if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
                throw "The downloaded repository is missing $requiredFile."
            }
        }

        Write-Host "Starting installer as administrator..."
        $process = Start-Process `
            -FilePath "$env:SystemRoot\System32\cmd.exe" `
            -ArgumentList "/d /c `"`"$launcher`"`"" `
            -Verb RunAs `
            -Wait `
            -PassThru

        if ($process.ExitCode -ne 0) {
            throw "Installer exited with code $($process.ExitCode)."
        }
    }
    finally {
        Write-Progress -Activity "Downloading installer" -Completed
        $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
        $expectedTempPrefix = Join-Path $tempBase "Install-"
        $isInstallerTemp = $resolvedTempRoot.StartsWith(
            $expectedTempPrefix,
            [StringComparison]::OrdinalIgnoreCase
        )

        if ($isInstallerTemp -and (Test-Path -LiteralPath $resolvedTempRoot)) {
            Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
