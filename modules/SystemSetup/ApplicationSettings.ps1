function Initialize-LocalApplicationDirectory {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and $parent -ne $Path) {
        Initialize-LocalApplicationDirectory -Path $parent
    }

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) {
        New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
        return
    }
    if (-not $item.PSIsContainer) {
        throw "Application settings directory is occupied by a file: '$Path'."
    }
    if ($item.LinkType -notin @("Junction", "SymbolicLink")) {
        return
    }

    # Materialize old directory links before writing any defaults. The linked
    # source stays intact, including files not managed by this repository.
    $stagingPath = Join-Path $parent (".settings-local-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stagingPath -ErrorAction Stop | Out-Null
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $stagingPath -Recurse -Force -ErrorAction Stop
    }
    $target = @($item.Target) | Select-Object -First 1
    [IO.Directory]::Delete($item.FullName)
    try {
        [IO.Directory]::Move($stagingPath, $item.FullName)
    }
    catch {
        New-Item -ItemType $item.LinkType -Path $Path -Target $target -ErrorAction Stop | Out-Null
        throw
    }
    Write-Host "[OK] Converted '$Path' to local settings; its former linked source was preserved."
}

function Merge-ApplicationPreferences {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Current,

        [Parameter(Mandatory)]
        [pscustomobject] $Defaults
    )

    foreach ($property in $Defaults.PSObject.Properties) {
        $existing = $Current.PSObject.Properties[$property.Name]
        if ($existing -and $existing.Value -is [pscustomobject] -and $property.Value -is [pscustomobject]) {
            Merge-ApplicationPreferences -Current $existing.Value -Defaults $property.Value
        }
        else {
            $Current | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
        }
    }
}

function Copy-RepositoryApplicationFile {
    param(
        [Parameter(Mandatory)]
        [string] $Source,

        [Parameter(Mandatory)]
        [string] $Destination,

        [Parameter()]
        [switch] $MergePreferences
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Repository application settings file is missing: '$Source'."
    }
    Initialize-LocalApplicationDirectory -Path (Split-Path -Parent $Destination)
    $item = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.PSIsContainer -or $item.LinkType)) {
        throw "Application settings file is a directory or filesystem link: '$Destination'."
    }
    if ([IO.Path]::GetExtension($Destination) -eq ".sqlite") {
        foreach ($suffix in @("-journal", "-wal", "-shm")) {
            if (Test-Path -LiteralPath "$Destination$suffix") {
                throw "SQLite recovery files exist for '$Destination'. Open and close the application before retrying."
            }
        }
    }

    $bytes = [IO.File]::ReadAllBytes($Source)
    if ($MergePreferences) {
        $defaults = [IO.File]::ReadAllText($Source) | ConvertFrom-Json -ErrorAction Stop
        $current = if ($item) {
            [IO.File]::ReadAllText($Destination) | ConvertFrom-Json -ErrorAction Stop
        }
        else { [pscustomobject] @{} }
        if ($defaults -isnot [pscustomobject] -or $current -isnot [pscustomobject]) {
            throw "Application preferences must be JSON objects: '$Destination'."
        }
        # Light Switch's location is deliberately absent from repository defaults.
        # Merge keeps any location already configured on this computer.
        Merge-ApplicationPreferences -Current $current -Defaults $defaults
        $text = ($current | ConvertTo-Json -Depth 100) + [Environment]::NewLine
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
    }
    $previousBytes = if ($item) { [IO.File]::ReadAllBytes($Destination) } else { $null }
    if ($item -and [Convert]::ToBase64String($previousBytes) -ceq [Convert]::ToBase64String($bytes)) {
        return
    }

    $temporaryPath = "$Destination.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllBytes($temporaryPath, $bytes)
        if ($item) {
            $actualBytes = [IO.File]::ReadAllBytes($Destination)
            if ([Convert]::ToBase64String($previousBytes) -cne [Convert]::ToBase64String($actualBytes)) {
                throw "Application settings changed during setup: '$Destination'."
            }
            $backup = "$Destination.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString('N'))"
            [IO.File]::Replace($temporaryPath, $Destination, $backup)
        }
        else {
            [IO.File]::Move($temporaryPath, $Destination)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop
        }
    }
    Write-Host "[OK] Applied repository settings to '$Destination'."
}

function Set-RepositoryApplicationSettings {
    param(
        [Parameter(Mandatory)]
        [string] $ResourcesRoot
    )

    $applications = @(
        @{
            Name = "X-Mouse Button Control"
            Processes = @("XMouseButtonControl")
            Source = "X-Mouse Button Control"
            Destination = Join-Path $env:APPDATA "Highresolution Enterprises\XMouseButtonControl"
            Files = @("XMBCSettings.xml")
        }
        @{
            Name = "foobar2000"
            Processes = @("foobar2000")
            Source = "foobar2000-v2"
            Destination = Join-Path $env:APPDATA "foobar2000-v2"
            Files = @("config.sqlite", "theme.fth", "playlists-v2.0\index.txt",
                "playlists-v2.0\playlist-8CD72BCC-0298-48EE-88C9-2783441A585F.fplite",
                "playlists-v2.0\playlist-8CD72BCC-0298-48EE-88C9-2783441A585F-props.sqlite")
        }
        @{
            Name = "FancyZones"
            Processes = @("PowerToys", "PowerToys.Settings", "PowerToys.FancyZones", "PowerToys.FancyZonesEditor")
            Source = "PowerToys\FancyZones"
            Destination = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones"
            Files = @("settings.json", "custom-layouts.json")
        }
        @{
            Name = "Light Switch"
            Processes = @("PowerToys", "PowerToys.Settings", "PowerToys.LightSwitch")
            Source = "PowerToys\LightSwitch"
            Destination = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\LightSwitch"
            Files = @("settings.json")
            MergePreferences = $true
        }
    )

    $commandPalettePackages = @(
        Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA "Packages") -Directory `
            -Filter "Microsoft.CommandPalette_*" -ErrorAction SilentlyContinue
    )
    foreach ($package in $commandPalettePackages) {
        $applications += @{
            Name = "Command Palette"
            Processes = @("PowerToys", "PowerToys.Settings", "Microsoft.CmdPal.UI", "PowerToys.CommandPalette")
            Source = "PowerToys\CommandPalette"
            Destination = Join-Path $package.FullName "LocalState"
            Files = @("settings.json")
        }
    }
    if ($commandPalettePackages.Count -eq 0) {
        Write-Host "[SKIP] Command Palette is not initialized. Launch it once and rerun setup to apply its settings."
    }

    foreach ($application in $applications) {
        if (Get-Process -Name $application.Processes -ErrorAction SilentlyContinue) {
            Write-Warning "Close $($application.Name) and rerun setup to apply its settings."
            continue
        }
        foreach ($file in $application.Files) {
            try {
                Copy-RepositoryApplicationFile `
                    -Source (Join-Path (Join-Path $ResourcesRoot $application.Source) $file) `
                    -Destination (Join-Path $application.Destination $file) `
                    -MergePreferences:([bool] $application.MergePreferences)
            }
            catch {
                Write-Warning "Failed to apply $($application.Name) settings: $($_.Exception.Message)"
            }
        }
    }
}
