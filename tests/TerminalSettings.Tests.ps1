BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psd1") -Force
    $defaultsPath = Join-Path $repositoryRoot "resources\Windows Terminal\settings.json"
    $terminalDefaults = Get-Content -LiteralPath $defaultsPath -Raw | ConvertFrom-Json
}

Describe "Targeted Windows Terminal preferences" {
    It "preserves comments, profiles, actions, schemes, themes, and unknown values on reruns" {
        InModuleScope SystemSetup -Parameters @{ Defaults = $terminalDefaults } {
            param($Defaults)
            $original = @'
{
    // Keep my profiles and future settings.
    "copyOnSelect": true,
    "copyFormatting": "all",
    "defaultProfile": "custom",
    "profiles": {
        "defaults": { "colorScheme": "Campbell", "font": { "face": "Consolas" } },
        "list": [{ "guid": "custom", "name": "My shell", "colorScheme": "Campbell" }],
    },
    "actions": [{ "id": "User.Custom", "command": "newTab" }],
    "schemes": [{ "name": "My scheme" }],
    "themes": [{ "name": "My theme" }],
    "newTabMenu": [{ "type": "profile", "profile": "custom" }],
    "futureSetting": [[null, "https://example.com/a/*literal*/", "quote: \"hello\""], true],
    /* Keep this block comment too. */
}
'@
            $updated = Merge-TerminalDefaults -Text $original -Defaults $Defaults
            $value = (Read-TerminalJson -Text $updated).Value
            $value.copyOnSelect | Should -BeFalse
            $value.copyFormatting | Should -Be "none"
            $value.defaultProfile | Should -Be $Defaults.defaultProfile
            $value.profiles.defaults.colorScheme | Should -Be "One Half Dark"
            $value.profiles.defaults.font.face | Should -Be "Consolas"
            $value.profiles.list[0].name | Should -Be "My shell"
            $value.profiles.list[0].colorScheme | Should -Be "Campbell"
            $value.actions[0].id | Should -Be "User.Custom"
            $value.schemes[0].name | Should -Be "My scheme"
            $value.themes[0].name | Should -Be "My theme"
            $value.newTabMenu[0].profile | Should -Be "custom"
            $value.futureSetting[0].Count | Should -Be 3
            $value.futureSetting[0][0] | Should -BeNullOrEmpty
            $value.futureSetting[0][1] | Should -Be "https://example.com/a/*literal*/"
            $value.futureSetting[0][2] | Should -Be 'quote: "hello"'
            $updated | Should -Match '// Keep my profiles and future settings\.'
            $updated | Should -Match '/\* Keep this block comment too\. \*/'
            Merge-TerminalDefaults -Text $updated -Defaults $Defaults | Should -BeExactly $updated
        }
    }

    It "inserts missing parents into empty and commented objects with either newline style" {
        InModuleScope SystemSetup -Parameters @{ Defaults = $terminalDefaults } {
            param($Defaults)
            foreach ($original in @('{}', "{`r`n    // empty`r`n}", '{ "profiles": { /* defaults go here */ } }')) {
                $updated = Merge-TerminalDefaults -Text $original -Defaults $Defaults
                $value = (Read-TerminalJson -Text $updated).Value
                $value.profiles.defaults.colorScheme | Should -Be "One Half Dark"
                $value.keybindings.Count | Should -Be 3
                Merge-TerminalDefaults -Text $updated -Defaults $Defaults | Should -BeExactly $updated
                if ($original.Contains("`r`n")) { $updated | Should -Not -Match '(?<!\r)\n' }
            }
        }
    }

    It "resolves managed chord conflicts while preserving other chords and legacy action definitions" {
        InModuleScope SystemSetup -Parameters @{ Defaults = $terminalDefaults } {
            param($Defaults)
            $original = @'
{
    "actions": [
        // Preserve this custom action in the command palette.
        { "id": "User.Legacy", "command": "newTab", "keys": ["CTRL+C", "ctrl+shift+x"] },
        { "command": "closeTab", "keys": "ctrl+v" }
    ],
    "keybindings": [
        { "id": "User.Custom", "keys": ["ctrl+c", "ctrl+alt+x"] },
        { "id": "User.Conflict", "keys": "d+shift+alt" },
        { "id": "User.Other", "keys": "ctrl+f" },
        { "id": "Terminal.CopyToClipboard", "keys": "CTRL+C" },
        { "id": "User.Duplicate", "keys": "ctrl+c" },
    ]
}
'@
            $updated = Merge-TerminalDefaults -Text $original -Defaults $Defaults
            $value = (Read-TerminalJson -Text $updated).Value
            $value.actions[0].id | Should -Be "User.Legacy"
            @($value.actions[0].keys) | Should -Be @("ctrl+shift+x")
            $value.actions[1].command | Should -Be "closeTab"
            @($value.actions[1].keys).Count | Should -Be 0
            @($value.keybindings | Where-Object id -eq "User.Custom")[0].keys | Should -Be @("ctrl+alt+x")
            @($value.keybindings | Where-Object id -eq "User.Other")[0].keys | Should -Be "ctrl+f"
            @($value.keybindings | Where-Object id -eq "User.Conflict").Count | Should -Be 0
            @($value.keybindings | Where-Object id -eq "User.Duplicate").Count | Should -Be 0
            foreach ($binding in $Defaults.keybindings) {
                @($value.keybindings | Where-Object id -eq $binding.id).Count | Should -Be 1
            }
            $updated | Should -Match '// Preserve this custom action'
            Merge-TerminalDefaults -Text $updated -Defaults $Defaults | Should -BeExactly $updated
        }
    }

    It "replicates the original preferences even when built-in actions have been redefined" {
        InModuleScope SystemSetup -Parameters @{ Defaults = $terminalDefaults } {
            param($Defaults)
            $original = @'
{
    "copyFormatting": "all",
    "copyOnSelect": true,
    "defaultProfile": "custom",
    "profiles": { "defaults": { "colorScheme": "Campbell" }, "list": [{ "guid": "custom", "name": "My shell" }] },
    "actions": [
        { "id": "Terminal.CopyToClipboard", "command": "closeWindow" },
        { "id": "Terminal.PasteFromClipboard", "command": "closeTab" },
        { "id": "Terminal.DuplicatePaneAuto", "command": "newTab" }
    ],
    "keybindings": [
        { "id": "Terminal.CopyToClipboard", "keys": ["ctrl+c", "ctrl+shift+c"] },
        { "id": "Terminal.PasteFromClipboard", "keys": "ctrl+v" },
        { "id": "Terminal.DuplicatePaneAuto", "keys": "alt+shift+d" }
    ]
}
'@
            $updated = Merge-TerminalDefaults -Text $original -Defaults $Defaults
            $value = (Read-TerminalJson -Text $updated).Value
            $value.copyFormatting | Should -Be "none"
            $value.copyOnSelect | Should -BeFalse
            $value.defaultProfile | Should -Be "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}"
            $value.profiles.defaults.colorScheme | Should -Be "One Half Dark"
            $commands = @{}
            foreach ($chord in @("ctrl+c", "ctrl+v", "alt+shift+d")) {
                $bindings = @($value.keybindings | Where-Object { @($_.keys) -contains $chord })
                $bindings.Count | Should -Be 1
                $definitions = @($value.actions | Where-Object id -eq $bindings[0].id)
                $definitions.Count | Should -Be 1
                $commands[$chord] = $definitions[0].command
            }
            $commands["ctrl+c"].action | Should -Be "copy"
            $commands["ctrl+c"].singleLine | Should -BeFalse
            $commands["ctrl+v"] | Should -Be "paste"
            $commands["alt+shift+d"].action | Should -Be "splitPane"
            $commands["alt+shift+d"].splitMode | Should -Be "duplicate"
            $commands["alt+shift+d"].split | Should -Be "auto"
            # Custom definitions and shortcuts outside the three managed chords survive.
            @($value.actions | Where-Object id -eq "Terminal.CopyToClipboard")[0].command | Should -Be "closeWindow"
            @($value.keybindings | Where-Object { @($_.keys) -contains "ctrl+shift+c" })[0].id |
                Should -Be "Terminal.CopyToClipboard"
            $value.profiles.list[0].name | Should -Be "My shell"
            Merge-TerminalDefaults -Text $updated -Defaults $Defaults | Should -BeExactly $updated
        }
    }

    It "repairs managed action commands and duplicate IDs while keeping labels and other actions" {
        InModuleScope SystemSetup -Parameters @{ Defaults = $terminalDefaults } {
            param($Defaults)
            $original = @'
{
    "actions": [
        { "id": "User.WindowsInstall.Copy", "command": "closeTab" },
        { "id": "User.Custom", "command": "newTab" },
        // Keep my label on the managed action.
        { "id": "User.WindowsInstall.Copy", "name": "My copy label", "command": { "action": "copy", "singleLine": true, "copyFormatting": "all" } },
        { "id": "User.WindowsInstall.Paste", "name": "My paste label" },
    ]
}
'@
            $updated = Merge-TerminalDefaults -Text $original -Defaults $Defaults
            $value = (Read-TerminalJson -Text $updated).Value
            $copy = @($value.actions | Where-Object id -eq "User.WindowsInstall.Copy")
            $copy.Count | Should -Be 1
            $copy[0].name | Should -Be "My copy label"
            $copy[0].command.action | Should -Be "copy"
            $copy[0].command.singleLine | Should -BeFalse
            $copy[0].command.PSObject.Properties.Name | Should -Not -Contain "copyFormatting"
            $paste = @($value.actions | Where-Object id -eq "User.WindowsInstall.Paste")
            $paste[0].name | Should -Be "My paste label"
            $paste[0].command | Should -Be "paste"
            @($value.actions | Where-Object id -eq "User.Custom")[0].command | Should -Be "newTab"
            $updated | Should -Match '// Keep my label on the managed action\.'
            Merge-TerminalDefaults -Text $updated -Defaults $Defaults | Should -BeExactly $updated
        }
    }

    It "does not clear user actions when an older repository patch contains an empty actions array" {
        InModuleScope SystemSetup {
            $original = '{ "actions": [{ "id": "User.Custom", "command": "newTab" }] }'
            $defaults = [pscustomobject] @{ actions = @() }
            Merge-TerminalDefaults -Text $original -Defaults $defaults | Should -BeExactly $original
        }
    }

    It "rejects malformed JSON, duplicate keys, and incompatible containers" {
        InModuleScope SystemSetup -Parameters @{ Defaults = $terminalDefaults } {
            param($Defaults)
            foreach ($original in @('', '[]', '{"a":1 "b":2}', '{"a":1,,}', '{"a":1,"a":2}',
                '{"a":1,"A":2}', '{/* unterminated', '{"a":"bad\q"}', '{"profiles":[]}', '{"keybindings":{}}', '{"actions":{}}')) {
                { Merge-TerminalDefaults -Text $original -Defaults $Defaults } | Should -Throw
            }
        }
    }
}

Describe "Terminal settings file safety" {
    It "backs up exact original bytes, writes UTF-8, and performs no writes on a rerun" {
        InModuleScope SystemSetup -Parameters @{ Defaults = $terminalDefaults; Root = $TestDrive } {
            param($Defaults, $Root)
            $path = Join-Path $Root "terminal\settings.json"
            New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
            $unicodeComment = -join @([char] 0x00e5, [char] 0x00e4, [char] 0x00f6)
            $original = "{`r`n // User comment: $unicodeComment`r`n `"copyOnSelect`": true`r`n}"
            [IO.File]::WriteAllText($path, $original, [Text.Encoding]::Unicode)
            $originalBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
            Set-TerminalSettingsFile -SettingsPath $path -Defaults $Defaults
            $backups = @(Get-ChildItem -LiteralPath (Split-Path $path) -Filter "settings.json.backup-*")
            $backups.Count | Should -Be 1
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($backups[0].FullName)) | Should -BeExactly $originalBytes
            $utf8 = [Text.UTF8Encoding]::new($false, $true)
            $utf8.GetString([IO.File]::ReadAllBytes($path)) | Should -Match "User comment: $unicodeComment"
            $before = [IO.File]::ReadAllText($path)
            $writeTime = [IO.File]::GetLastWriteTimeUtc($path)
            Set-TerminalSettingsFile -SettingsPath $path -Defaults $Defaults
            [IO.File]::ReadAllText($path) | Should -BeExactly $before
            [IO.File]::GetLastWriteTimeUtc($path) | Should -Be $writeTime
            @(Get-ChildItem -LiteralPath (Split-Path $path) -Filter "settings.json.backup-*").Count | Should -Be 1
            @(Get-ChildItem -LiteralPath (Split-Path $path) -Filter "*.tmp").Count | Should -Be 0
        }
    }

    It "creates settings after a fresh installation without making a backup" {
        InModuleScope SystemSetup -Parameters @{ Defaults = $terminalDefaults; Root = $TestDrive } {
            param($Defaults, $Root)
            $path = Join-Path $Root "fresh\LocalState\settings.json"
            Set-TerminalSettingsFile -SettingsPath $path -Defaults $Defaults
            $value = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $value.keybindings.Count | Should -Be 3
            $value.profiles.defaults.colorScheme | Should -Be "One Half Dark"
            @(Get-ChildItem -LiteralPath (Split-Path $path) -Filter "settings.json.backup-*").Count | Should -Be 0
        }
    }

    It "leaves malformed or incompatible existing files untouched without a backup" {
        InModuleScope SystemSetup -Parameters @{ Defaults = $terminalDefaults; Root = $TestDrive } {
            param($Defaults, $Root)
            $path = Join-Path $Root "invalid.json"
            foreach ($original in @('{ broken', '{"profiles":[]}', '{"keybindings":{}}')) {
                [IO.File]::WriteAllText($path, $original)
                { Set-TerminalSettingsFile -SettingsPath $path -Defaults $Defaults } | Should -Throw
                [IO.File]::ReadAllText($path) | Should -BeExactly $original
            }
            @(Get-ChildItem -LiteralPath $Root -Filter "invalid.json.backup-*").Count | Should -Be 0
        }
    }

    It "detects an intervening write and cleans up its temporary file" {
        InModuleScope SystemSetup -Parameters @{ Defaults = $terminalDefaults; Root = $TestDrive } {
            param($Defaults, $Root)
            $script:terminalRacePath = Join-Path $Root "race.json"
            [IO.File]::WriteAllText($script:terminalRacePath, '{}')
            Mock Merge-TerminalDefaults {
                [IO.File]::WriteAllText($script:terminalRacePath, '{"changed":true}')
                return '{"copyOnSelect":false}'
            }
            { Set-TerminalSettingsFile -SettingsPath $script:terminalRacePath -Defaults $Defaults } |
                Should -Throw "*changed during setup*"
            [IO.File]::ReadAllText($script:terminalRacePath) | Should -BeExactly '{"changed":true}'
            @(Get-ChildItem -LiteralPath $Root | Where-Object Name -like "race.json.*").Count | Should -Be 0
        }
    }

    It "rejects invalid UTF-8 without changing the existing bytes" {
        InModuleScope SystemSetup -Parameters @{ Defaults = $terminalDefaults; Root = $TestDrive } {
            param($Defaults, $Root)
            $path = Join-Path $Root "encoding.json"
            $original = [byte[]] @(123, 34, 120, 34, 58, 34, 255, 34, 125)
            [IO.File]::WriteAllBytes($path, $original)
            { Set-TerminalSettingsFile -SettingsPath $path -Defaults $Defaults } | Should -Throw
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) | Should -BeExactly ([Convert]::ToBase64String($original))
        }
    }
}

Describe "Terminal defaults phase" {
    BeforeEach {
        Mock Set-RepositoryApplicationSettings -ModuleName SystemSetup {}
        $originalLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive "appdata"
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
        Mock Get-Process -ModuleName SystemSetup { @() }
        Mock Write-Warning -ModuleName SystemSetup {}
    }

    AfterEach { $env:LOCALAPPDATA = $originalLocalAppData }

    It "finds stable, preview, and unpackaged installations and warns per failed file" {
        foreach ($relativePath in @(
            "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe",
            "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe",
            "Microsoft\Windows Terminal"
        )) {
            New-Item -ItemType Directory -Path (Join-Path $env:LOCALAPPDATA $relativePath) -Force | Out-Null
        }
        Mock Set-TerminalSettingsFile -ModuleName SystemSetup {
            if ($SettingsPath -like "*Preview*") { throw "invalid preview settings" }
        }
        Set-RepositoryApplicationDefaults -ResourcesRoot (Join-Path $repositoryRoot "resources")
        Should -Invoke Set-TerminalSettingsFile -ModuleName SystemSetup -Exactly -Times 3
        Should -Invoke Write-Warning -ModuleName SystemSetup -Exactly -Times 1 -ParameterFilter {
            $Message -like "*invalid preview settings*"
        }
    }

    It "warns without changing settings when Terminal is running" {
        Mock Get-Process -ModuleName SystemSetup { [pscustomobject] @{ ProcessName = "WindowsTerminal" } }
        Mock Set-TerminalSettingsFile -ModuleName SystemSetup {}
        Set-RepositoryApplicationDefaults -ResourcesRoot (Join-Path $repositoryRoot "resources")
        Should -Invoke Set-TerminalSettingsFile -ModuleName SystemSetup -Times 0
        Should -Invoke Write-Warning -ModuleName SystemSetup -Exactly -Times 1 -ParameterFilter {
            $Message -like "*Close Windows Terminal*"
        }
    }
}
