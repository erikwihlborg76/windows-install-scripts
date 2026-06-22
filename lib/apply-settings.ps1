function Disable-NetworkAdapterWake {
    $disabledCount = 0

    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Querying wake-armed network devices."

    try {
        $networkDevices = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        Get-NetAdapter -Physical -IncludeHidden -ErrorAction Stop |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.InterfaceDescription)
            } |
            ForEach-Object {
                [void]$networkDevices.Add($_.InterfaceDescription.Trim())
            }
    }
    catch {
        Write-Warn "Failed to query physical network adapters: $($_.Exception.Message)"
        return
    }

    $wakeArmedDevices = @(
        powercfg.exe -devicequery wake_armed 2>$null |
            ForEach-Object { $_.Trim() } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -ine "NONE"
            }
    )

    foreach ($device in $wakeArmedDevices) {
        if (-not $networkDevices.Contains($device)) {
            Write-LogLine "Leaving non-network wake device enabled: $device"
            continue
        }

        Write-Host "  - Disabling network wake on: `"$device`""
        Write-LogLine "Disabling network wake on: $device"

        & powercfg.exe -devicedisablewake "$device" 1>> $script:Log 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Failed to disable network wake on: $device"
        }
        else {
            $disabledCount++
            Write-Ok "Disabled network wake on: $device"
        }
    }

    if ($disabledCount -eq 0) {
        Write-Ok "No wake-armed network devices found."
    }
}

function Disable-WakeTimers {
    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Disabling wake timers for current power scheme."

    & powercfg.exe /SETACVALUEINDEX SCHEME_CURRENT SUB_SLEEP RTCWAKE 0 1>> $script:Log 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Failed to disable AC wake timers."
    }
    else {
        Write-Ok "Disabled AC wake timers."
    }

    & powercfg.exe /SETDCVALUEINDEX SCHEME_CURRENT SUB_SLEEP RTCWAKE 0 1>> $script:Log 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Failed to disable DC wake timers."
    }
    else {
        Write-Ok "Disabled DC wake timers."
    }

    & powercfg.exe /SETACTIVE SCHEME_CURRENT 1>> $script:Log 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Failed to re-apply current power scheme."
    }
    else {
        Write-Ok "Re-applied current power scheme."
    }
}

function Copy-WindowsTerminalSettings {
    param(
        [Parameter(Mandatory)]
        [string] $ResourcesDir
    )

    Write-Host ""
    Write-Host "========== Windows Terminal =========="

    $wtSettings = Join-Path $ResourcesDir "Windows Terminal\settings.json"

    if (-not (Test-Path -LiteralPath $wtSettings -PathType Leaf)) {
        Write-Warn "Missing Windows Terminal settings: $wtSettings"
        return
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA "Packages"

    $terminalPackages = Get-ChildItem `
        -LiteralPath $packagesRoot `
        -Directory `
        -Filter "Microsoft.WindowsTerminal_*" `
        -ErrorAction SilentlyContinue

    if (-not $terminalPackages) {
        Write-Warn "No Microsoft.WindowsTerminal package folder found."
        return
    }

    foreach ($package in $terminalPackages) {
        $localState = Join-Path $package.FullName "LocalState"
        $destination = Join-Path $localState "settings.json"

        New-Item -ItemType Directory -Path $localState -Force | Out-Null

        try {
            Copy-Item -LiteralPath $wtSettings -Destination $destination -Force
            Write-Ok "Copied Windows Terminal settings to $destination"
        }
        catch {
            Write-Warn "Failed to copy Windows Terminal settings to $destination"
        }
    }
}

function Copy-PowerToysSettings {
    param(
        [Parameter(Mandatory)]
        [string] $SyncRoot
    )

    Write-Host ""
    Write-Host "========== PowerToys settings =========="

    if ([string]::IsNullOrWhiteSpace($SyncRoot)) {
        Write-Info "No sync root supplied; skipping private PowerToys settings."
        return
    }

    $sourceRoot = Join-Path $SyncRoot "Apps-data\PowerToys"
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
        Write-Info "Private PowerToys settings not found, skipping: $sourceRoot"
        return
    }

    Invoke-RoboCopySafe `
        -SourceFolder (Join-Path $sourceRoot "FancyZones") `
        -DestinationFolder (Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones")

    Invoke-RoboCopySafe `
        -SourceFolder (Join-Path $sourceRoot "LightSwitch") `
        -DestinationFolder (Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\LightSwitch")

    $commandPaletteSettings = Join-Path $sourceRoot "CommandPalette\settings.json"
    if (-not (Test-Path -LiteralPath $commandPaletteSettings -PathType Leaf)) {
        Write-Info "Private Command Palette settings not found, skipping: $commandPaletteSettings"
        return
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA "Packages"
    $commandPalettePackages = Get-ChildItem `
        -LiteralPath $packagesRoot `
        -Directory `
        -Filter "Microsoft.CommandPalette_*" `
        -ErrorAction SilentlyContinue

    if (-not $commandPalettePackages) {
        Write-Warn "No Microsoft Command Palette package folder found."
        return
    }

    foreach ($package in $commandPalettePackages) {
        $localState = Join-Path $package.FullName "LocalState"
        $destination = Join-Path $localState "settings.json"

        try {
            New-Item -ItemType Directory -Path $localState -Force | Out-Null
            Copy-Item -LiteralPath $commandPaletteSettings -Destination $destination -Force
            Write-Ok "Copied Command Palette settings to $destination"
        }
        catch {
            Write-Warn "Failed to copy Command Palette settings to $destination. $($_.Exception.Message)"
        }
    }
}

function Disable-ScheduledTaskByName {
    param([Parameter(Mandatory)][string] $TaskName)

    $normalizedTaskName = if ($TaskName.StartsWith("\")) {
        $TaskName
    }
    else {
        "\$TaskName"
    }

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # schtasks.exe reports a missing task on the error stream. Allow the
        # exit code below to handle that expected result without terminating.
        $ErrorActionPreference = "Continue"
        & schtasks.exe /Query /TN $normalizedTaskName 1>$null 2>$null
        $queryExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($queryExitCode -ne 0) {
        Write-Info "Scheduled task not found, skipping: $normalizedTaskName"
        return
    }

    try {
        $ErrorActionPreference = "Continue"
        & schtasks.exe /Change /TN $normalizedTaskName /Disable 1>$null 2>$null
        $changeExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($changeExitCode -ne 0) {
        Write-Warn "Failed to disable scheduled task: $normalizedTaskName"
        return
    }

    Write-Ok "Disabled scheduled task: $normalizedTaskName"
}

function Disable-Service {
    param([Parameter(Mandatory)][string] $Name)

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & sc.exe query $Name 1>$null 2>$null
        $queryExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($queryExitCode -ne 0) {
        Write-Info "Service not found, skipping: $Name"
        return
    }

    try {
        $ErrorActionPreference = "Continue"
        & sc.exe config $Name "start=" "disabled" 1>$null 2>$null
        $changeExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($changeExitCode -ne 0) {
        Write-Warn "Failed to disable service: $Name"
        return
    }

    Write-Ok "Disabled service: $Name"
}

function Import-Lgpo {
    param(
        [Parameter(Mandatory)]
        [string] $ResourcesDir
    )

    Write-Host ""
    Write-Host "========== LGPO import =========="

    $lgpoTxt = Join-Path $ResourcesDir "LGPO\global_policy_objects.txt"

    $lgpoCommand = Get-Command -Name "LGPO.exe" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    $lgpoCandidates = @(
        if ($lgpoCommand) {
            $lgpoCommand.Source
        }

        if ($env:LOCALAPPDATA) {
            Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\LGPO.exe"
        }

        if ($env:ProgramFiles) {
            Join-Path $env:ProgramFiles "WinGet\Links\LGPO.exe"
        }
    )

    $lgpoExe = $lgpoCandidates |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            (Test-Path -LiteralPath $_ -PathType Leaf)
        } |
        Select-Object -First 1

    if (-not $lgpoExe) {
        Write-Warn "LGPO.exe was not found. Install package Microsoft.SecurityComplianceToolkit.LGPO with WinGet."
        return
    }

    if (-not (Test-Path -LiteralPath $lgpoTxt -PathType Leaf)) {
        Write-Warn "LGPO text file not found: $lgpoTxt"
        return
    }

    Write-Host "Importing LGPO settings..."
    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] LGPO import: `"$lgpoTxt`""

    $lgpoStdOut = Join-Path $env:TEMP "LGPO.stdout.log"
    $lgpoStdErr = Join-Path $env:TEMP "LGPO.stderr.log"

    Remove-Item -LiteralPath $lgpoStdOut, $lgpoStdErr -Force -ErrorAction SilentlyContinue

    try {
        $process = Start-Process `
            -FilePath $lgpoExe `
            -ArgumentList @("/t", "`"$lgpoTxt`"") `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $lgpoStdOut `
            -RedirectStandardError $lgpoStdErr

        foreach ($outputFile in @($lgpoStdOut, $lgpoStdErr)) {
            if (Test-Path -LiteralPath $outputFile -PathType Leaf) {
                Get-Content -LiteralPath $outputFile -ErrorAction SilentlyContinue |
                    ForEach-Object { Write-LogLine $_ }
            }
        }

        if ($process.ExitCode -ne 0) {
            Write-Warn "LGPO import failed with exit code $($process.ExitCode). See log: $script:Log"
            return
        }

        Write-Ok "LGPO import completed."
    }
    catch {
        $message = $_.Exception.Message

        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = ($_ | Out-String).Trim()
        }

        Write-Warn "LGPO import failed to start or complete. $message"
    }
}
