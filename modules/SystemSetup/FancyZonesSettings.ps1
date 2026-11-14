function Get-FancyZonesCliPath {
    $command = Get-Command -Name "PowerToys.FancyZones.CLI.exe" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return $command.Source }

    # A newly installed PowerToys may not be on this process's existing PATH yet.
    foreach ($root in @($env:LOCALAPPDATA, $env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) {
        $candidate = Join-Path $root "PowerToys\bin\PowerToys.FancyZones.CLI.exe"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Start-FancyZonesForSetup {
    param(
        [Parameter(Mandatory)]
        [string] $CliPath
    )

    if (Get-Process -Name "PowerToys.FancyZones" -ErrorAction SilentlyContinue) { return }
    if (-not (Get-Process -Name "PowerToys" -ErrorAction SilentlyContinue)) {
        $powerToys = Join-Path (Split-Path -Parent (Split-Path -Parent $CliPath)) "PowerToys.exe"
        if (-not (Test-Path -LiteralPath $powerToys -PathType Leaf)) {
            throw "PowerToys.exe was not found beside the FancyZones CLI."
        }
        Start-Process -FilePath $powerToys -WindowStyle Hidden -ErrorAction Stop
    }
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if (Get-Process -Name "PowerToys.FancyZones" -ErrorAction SilentlyContinue) { return }
        Start-Sleep -Milliseconds 500
    }
    throw "FancyZones did not start. Enable FancyZones in PowerToys and rerun setup."
}

function Set-RepositoryFancyZonesLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ResourcesRoot
    )

    try {
        $cli = Get-FancyZonesCliPath
        if (-not $cli) {
            throw "FancyZones CLI was not found. Install or update PowerToys and rerun setup."
        }
        $source = Join-Path $ResourcesRoot "PowerToys\FancyZones\custom-layouts.json"
        $layouts = @(([IO.File]::ReadAllText($source) | ConvertFrom-Json -ErrorAction Stop).'custom-layouts')
        $layoutGuid = [guid]::Empty
        if ($layouts.Count -ne 1 -or -not [guid]::TryParse([string] $layouts[0].uuid, [ref] $layoutGuid)) {
            throw "Repository FancyZones settings must contain exactly one custom layout with a valid UUID."
        }
        $layoutId = $layoutGuid.ToString("B").ToUpperInvariant()
        $local = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones\custom-layouts.json"
        $installedLayouts = @(([IO.File]::ReadAllText($local) | ConvertFrom-Json -ErrorAction Stop).'custom-layouts')
        if (@($installedLayouts | Where-Object { $_.uuid -eq $layoutId }).Count -eq 0) {
            throw "The repository layout was not imported. Close PowerToys and rerun setup to restore its settings first."
        }

        $desktopCli = Get-VirtualDesktopTool
        $count = Invoke-SetupNativeCommand -FilePath $desktopCli -Arguments @("/Quiet", "/Count")
        $current = Invoke-SetupNativeCommand -FilePath $desktopCli -Arguments @("/Quiet", "/GetCurrentDesktop")
        if ($count.ExitCode -lt 1 -or $current.ExitCode -lt 0 -or $current.ExitCode -ge $count.ExitCode) {
            throw "Could not enumerate the virtual desktops or determine the starting desktop."
        }
        Start-FancyZonesForSetup -CliPath $cli

        $startingDesktop = $current.ExitCode
        $activeDesktop = $startingDesktop
        $switchAttempted = $false
        $switchOptions = @("/Quiet")
        if ([IO.Path]::GetFileName($desktopCli) -like "VirtualDesktop11*") {
            $switchOptions += "/Animation:Off"
        }
        try {
            for ($index = 0; $index -lt $count.ExitCode; $index++) {
                if ($index -ne $activeDesktop) {
                    $switchAttempted = $true
                    $switched = Invoke-SetupNativeCommand -FilePath $desktopCli -Arguments ($switchOptions + "/Switch:$index")
                    if ($switched.ExitCode -ne $index) { throw "Could not switch to virtual desktop $index." }
                    $activeDesktop = $index
                    # Allow FancyZones to process the desktop change before it
                    # refreshes its monitor metadata for the layout command.
                    Start-Sleep -Milliseconds 500
                }
                # --all means all monitors on the currently active desktop.
                $result = Invoke-SetupNativeCommand -FilePath $cli -Arguments @("set-layout", $layoutId, "--all")
                if ($result.ExitCode -ne 0) {
                    throw "FancyZones failed on virtual desktop $index (exit $($result.ExitCode)): $($result.Output -join ' ')"
                }
            }
        }
        finally {
            if ($switchAttempted) {
                try {
                    $restored = Invoke-SetupNativeCommand -FilePath $desktopCli -Arguments ($switchOptions + "/Switch:$startingDesktop")
                    if ($restored.ExitCode -ne $startingDesktop) { throw "Desktop switch failed." }
                }
                catch {
                    Write-Warning "Could not restore starting virtual desktop ${startingDesktop}: $($_.Exception.Message)"
                }
            }
        }
        Write-Host "[OK] Applied FancyZones layout $layoutId to all monitors on $($count.ExitCode) virtual desktop(s)."
    }
    catch {
        Write-Warning "Failed to apply the repository FancyZones layout: $($_.Exception.Message)"
    }
}
