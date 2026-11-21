BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psd1") -Force
}

Describe "Visual Studio Code context menu" {
    It "quotes the installed <Location> executable and folder argument in a per-user shell verb" -TestCases @(
        @{ Location = "User" }
        @{ Location = "System64" }
        @{ Location = "System32" }
    ) {
        param($Location)
        InModuleScope SystemSetup -Parameters @{ Location = $Location; Root = $TestDrive } {
            param($Location, $Root)
            $savedVariables = @{}
            foreach ($name in @("LOCALAPPDATA", "ProgramW6432", "ProgramFiles", "ProgramFiles(x86)")) {
                $savedVariables[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
                [Environment]::SetEnvironmentVariable($name, (Join-Path $Root "$name with spaces"), "Process")
            }
            try {
                $script:fixtureCodeExecutable = switch ($Location) {
                    "User" { Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\Code.exe" }
                    "System64" { Join-Path $env:ProgramW6432 "Microsoft VS Code\Code.exe" }
                    "System32" { Join-Path ${env:ProgramFiles(x86)} "Microsoft VS Code\Code.exe" }
                }
                Mock Test-Path { $LiteralPath -eq $script:fixtureCodeExecutable }
                Mock Set-ConfiguredRegistryValues {}
                Mock Write-Warning {}
                Set-VisualStudioCodeContextMenu
                Should -Invoke Set-ConfiguredRegistryValues -Times 1 -Exactly -ParameterFilter {
                    $Settings.Count -eq 2 -and
                    $Settings[0].Path -eq 'HKCU:\Software\Classes\Directory\Background\shell\open_vscode' -and
                    $Settings[1].Path -eq 'HKCU:\Software\Classes\Directory\Background\shell\open_vscode\command' -and
                    $Settings[1].Type -eq "String" -and
                    $Settings[1].Value -eq ('"{0}" "%V"' -f $script:fixtureCodeExecutable)
                }
                Should -Invoke Write-Warning -Times 0 -Exactly
            }
            finally {
                foreach ($name in $savedVariables.Keys) {
                    [Environment]::SetEnvironmentVariable($name, $savedVariables[$name], "Process")
                }
            }
        }
    }

    It "warns without writing shell entries when VS Code is absent" {
        InModuleScope SystemSetup {
            Mock Test-Path { $false }
            Mock Set-ConfiguredRegistryValues {}
            Mock Write-Warning {}
            Set-VisualStudioCodeContextMenu
            Should -Invoke Set-ConfiguredRegistryValues -Times 0 -Exactly
            Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like '*Visual Studio Code*skipped*' }
        }
    }
}

Describe "Repository application settings" {
    BeforeEach {
        $savedRoaming = $env:APPDATA
        $savedLocal = $env:LOCALAPPDATA
        $env:APPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString("N") + "\Roaming")
        $env:LOCALAPPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString("N") + "\Local")
        New-Item -ItemType Directory -Path $env:APPDATA, $env:LOCALAPPDATA -Force | Out-Null
        Mock Get-Process -ModuleName SystemSetup { @() }
        Mock Set-XMouseStartupShortcut -ModuleName SystemSetup {}
        Mock Write-Warning -ModuleName SystemSetup {}
    }

    AfterEach {
        $env:APPDATA = $savedRoaming
        $env:LOCALAPPDATA = $savedLocal
    }

    It "installs settings and radio playlists without any sync provider and is unchanged on rerun" {
        $packageRoot = Join-Path $env:LOCALAPPDATA "Packages\Microsoft.CommandPalette_fixture"
        New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
        $resources = Join-Path $repositoryRoot "resources"
        InModuleScope SystemSetup -Parameters @{ Resources = $resources } {
            param($Resources)
            Set-RepositoryApplicationSettings -ResourcesRoot $Resources
        }
        $expected = @(
            @{ Source = "X-Mouse Button Control\XMBCSettings.xml"; Target = Join-Path $env:APPDATA "Highresolution Enterprises\XMouseButtonControl\XMBCSettings.xml" }
            @{ Source = "PowerToys\FancyZones\custom-layouts.json"; Target = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones\custom-layouts.json" }
            @{ Source = "PowerToys\FancyZones\settings.json"; Target = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones\settings.json" }
            @{ Source = "PowerToys\CommandPalette\settings.json"; Target = Join-Path $packageRoot "LocalState\settings.json" }
            @{ Source = "foobar2000-v2\config.sqlite"; Target = Join-Path $env:APPDATA "foobar2000-v2\config.sqlite" }
            @{ Source = "foobar2000-v2\theme.fth"; Target = Join-Path $env:APPDATA "foobar2000-v2\theme.fth" }
        )
        foreach ($file in $expected) {
            (Get-FileHash -LiteralPath $file.Target).Hash |
                Should -Be (Get-FileHash -LiteralPath (Join-Path $resources $file.Source)).Hash
        }
        $playlistRoot = Join-Path $env:APPDATA "foobar2000-v2\playlists-v2.0"
        @(Get-ChildItem -LiteralPath $playlistRoot -File).Count | Should -Be 3
        $playlist = Get-ChildItem -LiteralPath $playlistRoot -Filter "*.fplite"
        [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($playlist.FullName)) |
            Should -Match 'stream\.radioparadise\.com/'
        $settingsFiles = @(Get-ChildItem -LiteralPath $env:APPDATA, $env:LOCALAPPDATA -Recurse -File)
        $timestamps = @($settingsFiles | ForEach-Object LastWriteTimeUtc)
        InModuleScope SystemSetup -Parameters @{ Resources = $resources } {
            param($Resources)
            Set-RepositoryApplicationSettings -ResourcesRoot $Resources
        }
        @($settingsFiles | ForEach-Object { [IO.File]::GetLastWriteTimeUtc($_.FullName) }) |
            Should -Be $timestamps
        @(Get-ChildItem -LiteralPath $env:APPDATA, $env:LOCALAPPDATA -Recurse -Filter "*.backup-*").Count |
            Should -Be 0
        Should -Invoke Write-Warning -ModuleName SystemSetup -Times 0 -Exactly
    }

    It "preserves local Light Switch coordinates and unrelated properties" {
        $settings = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\LightSwitch\settings.json"
        New-Item -ItemType Directory -Path (Split-Path $settings) -Force | Out-Null
        $original = '{"properties":{"latitude":{"value":"1"},"longitude":{"value":"2"},"changeApps":{"value":false}},"futureSetting":true}'
        [IO.File]::WriteAllText($settings, $original)
        InModuleScope SystemSetup -Parameters @{ Resources = (Join-Path $repositoryRoot "resources") } {
            param($Resources)
            Set-RepositoryApplicationSettings -ResourcesRoot $Resources
        }
        $actual = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
        $actual.properties.latitude.value | Should -Be "1"
        $actual.properties.longitude.value | Should -Be "2"
        $actual.properties.changeApps.value | Should -BeTrue
        $actual.futureSetting | Should -BeTrue
        $backups = @(Get-ChildItem -LiteralPath (Split-Path $settings) -Filter "settings.json.backup-*")
        $backups.Count | Should -Be 1
        [IO.File]::ReadAllText($backups[0].FullName) | Should -BeExactly $original
        $publicDefaults = Get-Content -LiteralPath (Join-Path $repositoryRoot "resources\PowerToys\LightSwitch\settings.json") -Raw | ConvertFrom-Json
        $publicDefaults.properties.PSObject.Properties.Name | Should -Not -Contain "latitude"
        $publicDefaults.properties.PSObject.Properties.Name | Should -Not -Contain "longitude"
    }

    It "materializes old application and playlist junctions without changing their targets" {
        $external = Join-Path $TestDrive ([guid]::NewGuid().ToString("N") + "\external")
        $vendorSource = Join-Path $external "vendor"
        $playlistSource = Join-Path $external "playlists"
        $vendorLink = Join-Path $env:APPDATA "Highresolution Enterprises"
        $playlistLink = Join-Path $env:APPDATA "foobar2000-v2\playlists-v2.0"
        New-Item -ItemType Directory -Path (Join-Path $vendorSource "XMouseButtonControl"), $playlistSource, (Split-Path $playlistLink) -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $vendorSource "XMouseButtonControl\XMBCSettings.xml"), '<original/>')
        [IO.File]::WriteAllText((Join-Path $vendorSource "keep.txt"), 'unmanaged')
        [IO.File]::WriteAllText((Join-Path $playlistSource "index.txt"), 'original playlist')
        New-Item -ItemType Junction -Path $vendorLink -Target $vendorSource | Out-Null
        New-Item -ItemType Junction -Path $playlistLink -Target $playlistSource | Out-Null
        try {
            InModuleScope SystemSetup -Parameters @{ Resources = (Join-Path $repositoryRoot "resources") } {
                param($Resources)
                Set-RepositoryApplicationSettings -ResourcesRoot $Resources
            }
            (Get-Item -LiteralPath $vendorLink).LinkType | Should -BeNullOrEmpty
            (Get-Item -LiteralPath $playlistLink).LinkType | Should -BeNullOrEmpty
            [IO.File]::ReadAllText((Join-Path $vendorSource "XMouseButtonControl\XMBCSettings.xml")) | Should -BeExactly '<original/>'
            [IO.File]::ReadAllText((Join-Path $playlistSource "index.txt")) | Should -BeExactly 'original playlist'
            [IO.File]::ReadAllText((Join-Path $vendorLink "keep.txt")) | Should -BeExactly 'unmanaged'
            @(Get-ChildItem -LiteralPath (Join-Path $vendorLink "XMouseButtonControl") -Filter "*.backup-*").Count | Should -Be 1
            Should -Invoke Write-Warning -ModuleName SystemSetup -Times 0 -Exactly
        }
        finally {
            foreach ($link in @($vendorLink, $playlistLink)) {
                if ((Get-Item -LiteralPath $link -ErrorAction SilentlyContinue).LinkType) {
                    [IO.Directory]::Delete($link)
                }
            }
        }
    }

    It "skips running applications without touching their settings or links" {
        Mock Get-Process -ModuleName SystemSetup { [pscustomobject] @{ ProcessName = "running" } }
        InModuleScope SystemSetup -Parameters @{ Resources = (Join-Path $repositoryRoot "resources") } {
            param($Resources)
            Set-RepositoryApplicationSettings -ResourcesRoot $Resources
        }
        @(Get-ChildItem -LiteralPath $env:APPDATA, $env:LOCALAPPDATA -Recurse -File).Count | Should -Be 0
        Should -Invoke Write-Warning -ModuleName SystemSetup -Times 4 -Exactly
    }

    It "runs application restoration even when Windows Terminal is unavailable" {
        Set-RepositoryApplicationDefaults -ResourcesRoot (Join-Path $repositoryRoot "resources")
        Test-Path -LiteralPath (Join-Path $env:APPDATA "Highresolution Enterprises\XMouseButtonControl\XMBCSettings.xml") |
            Should -BeTrue
        Test-Path -LiteralPath (Join-Path $env:APPDATA "foobar2000-v2\config.sqlite") |
            Should -BeTrue
        Should -Invoke Write-Warning -ModuleName SystemSetup -Times 1 -Exactly -ParameterFilter {
            $Message -like '*Terminal*'
        }
    }

    It "preserves malformed settings, directory collisions, and SQLite databases with recovery files" {
        InModuleScope SystemSetup -Parameters @{ Root = $TestDrive } {
            param($Root)
            $source = Join-Path $Root "source.json"
            $invalid = Join-Path $Root "invalid.json"
            [IO.File]::WriteAllText($source, '{"new":true}')
            [IO.File]::WriteAllText($invalid, '{ broken')
            { Copy-RepositoryApplicationFile -Source $source -Destination $invalid -MergePreferences } | Should -Throw
            [IO.File]::ReadAllText($invalid) | Should -BeExactly '{ broken'
            $database = Join-Path $Root "existing.sqlite"
            [IO.File]::WriteAllText($database, 'original database')
            [IO.File]::WriteAllText("$database-journal", 'pending recovery')
            { Copy-RepositoryApplicationFile -Source $source -Destination $database } | Should -Throw '*recovery*'
            [IO.File]::ReadAllText($database) | Should -BeExactly 'original database'
            $directory = Join-Path $Root "directory.json"
            New-Item -ItemType Directory -Path $directory | Out-Null
            { Copy-RepositoryApplicationFile -Source $source -Destination $directory } | Should -Throw '*directory or filesystem link*'
        }
    }
}

Describe "X-Mouse Button Control Startup shortcut" {
    It "creates a current-user shortcut for an installed app and leaves it unchanged on rerun" {
        InModuleScope SystemSetup -Parameters @{ Root = $TestDrive } {
            param($Root)
            $programs = Join-Path $Root "Program Files (x86)"
            $startup = Join-Path $Root "User Startup"
            $executable = Join-Path $programs "Highresolution Enterprises\X-Mouse Button Control\XMouseButtonControl.exe"
            New-Item -ItemType Directory -Path (Split-Path $executable) -Force | Out-Null
            [IO.File]::WriteAllText($executable, "fixture; never executed")
            $searchRoots = @((Join-Path $Root "Program Files"), $programs)
            Set-XMouseStartupShortcut -ProgramDirectories $searchRoots -StartupDirectory $startup
            $shortcutPath = Join-Path $startup "X-Mouse Button Control.lnk"
            Test-Path -LiteralPath $shortcutPath -PathType Leaf | Should -BeTrue
            $shell = $null
            $shortcut = $null
            try {
                $shell = New-Object -ComObject WScript.Shell
                $shortcut = $shell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath | Should -Be $executable
                $shortcut.Arguments | Should -Be "/notportable /delay /NoLog"
                $shortcut.WorkingDirectory | Should -Be (Split-Path $executable)
            }
            finally {
                if ($shortcut) { [void] [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
                if ($shell) { [void] [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
            }
            $writeTime = [IO.File]::GetLastWriteTimeUtc($shortcutPath)
            Set-XMouseStartupShortcut -ProgramDirectories $searchRoots -StartupDirectory $startup
            [IO.File]::GetLastWriteTimeUtc($shortcutPath) | Should -Be $writeTime
        }
    }

    It "creates no shortcut or Startup directory when the app is absent" {
        InModuleScope SystemSetup -Parameters @{ Root = $TestDrive } {
            param($Root)
            $startup = Join-Path $Root "Absent App Startup"
            Set-XMouseStartupShortcut -ProgramDirectories @((Join-Path $Root "Missing Programs")) -StartupDirectory $startup
            Test-Path -LiteralPath $startup | Should -BeFalse
        }
    }
}
