BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot "modules\SyncProfile\SyncProfile.psd1") -Force
    $syncModule = Get-Module SyncProfile

    function New-TestSyncRoot {
        param([string] $Path)
        New-Item -ItemType Directory -Path (Join-Path $Path "Apps"), (Join-Path $Path "Apps-data") -Force | Out-Null
        return $Path
    }

    function Set-TestSshConfiguration {
        param([string] $ProfilePath)
        & $syncModule {
            param($Path)
            Set-SshIncludeConfiguration -UserProfile $Path
        } $ProfilePath
    }
}

Describe "Resolve-SyncRoot" {
    It "accepts an explicit valid sync root without provider-specific discovery" {
        $syncRoot = Join-Path $TestDrive "sync"
        New-Item -ItemType Directory -Path (Join-Path $syncRoot "Apps") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $syncRoot "Apps-data") -Force | Out-Null

        $resolved = Resolve-SyncRoot `
            -SyncProvider OneDrive `
            -SyncRootOverride $syncRoot

        $expected = (Resolve-Path $syncRoot).ProviderPath
        if ($resolved -ne $expected) {
            throw "Expected resolved root '$expected'; received '$resolved'."
        }
    }

    It "rejects a root without Apps-data" {
        $syncRoot = Join-Path $TestDrive "incomplete"
        New-Item -ItemType Directory -Path (Join-Path $syncRoot "Apps") -Force | Out-Null

        $threw = $false
        try {
            Resolve-SyncRoot -SyncProvider Dropbox -SyncRootOverride $syncRoot
        }
        catch {
            $threw = $true
        }

        if (-not $threw) {
            throw "Resolve-SyncRoot accepted a root without Apps-data."
        }
    }
}

Describe "Sync-backed SSH configuration" {
    It "creates the current user's SSH config with the synced include" {
        $userProfile = Join-Path $TestDrive "new-profile"
        $syncModule = Get-Module SyncProfile

        & $syncModule {
            param($ProfilePath)
            Set-SshIncludeConfiguration -UserProfile $ProfilePath
        } $userProfile

        $sshConfig = Join-Path $userProfile ".ssh\config"
        if (-not (Test-Path -LiteralPath $sshConfig -PathType Leaf)) {
            throw "SSH config was not created: $sshConfig"
        }

        $actual = (Get-Content -LiteralPath $sshConfig -Raw).Trim()
        if ($actual -ne "Include c:/Apps-data/SSH/config") {
            throw "Unexpected SSH config content: $actual"
        }
    }

    It "preserves existing SSH settings and does not duplicate the include" {
        $userProfile = Join-Path $TestDrive "existing-profile"
        $sshDirectory = Join-Path $userProfile ".ssh"
        $sshConfig = Join-Path $sshDirectory "config"
        New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
        [IO.File]::WriteAllText($sshConfig, "Host example.com`r`n    User localuser")
        $syncModule = Get-Module SyncProfile

        1..2 | ForEach-Object {
            & $syncModule {
                param($ProfilePath)
                Set-SshIncludeConfiguration -UserProfile $ProfilePath
            } $userProfile
        }

        $lines = @(Get-Content -LiteralPath $sshConfig)
        if ($lines -notcontains "Host example.com" -or $lines -notcontains "    User localuser") {
            throw "Existing SSH configuration was not preserved."
        }

        $includeCount = @(
            $lines | Where-Object { $_ -ieq "Include c:/Apps-data/SSH/config" }
        ).Count
        if ($includeCount -ne 1) {
            throw "Expected exactly one synced SSH include; found $includeCount."
        }

        [IO.File]::ReadAllText($sshConfig) |
            Should -BeExactly "Host example.com`r`n    User localuser`r`nHost *`r`nInclude c:/Apps-data/SSH/config`r`n"
    }
}

Describe "Dropbox account discovery" {
    BeforeEach {
        $originalAppData = $env:APPDATA
        $originalLocalAppData = $env:LOCALAPPDATA
        $env:APPDATA = Join-Path $TestDrive "Roaming"
        $env:LOCALAPPDATA = Join-Path $TestDrive "Local"
        New-Item -ItemType Directory -Path (Join-Path $env:APPDATA "Dropbox"), (Join-Path $env:LOCALAPPDATA "Dropbox") -Force | Out-Null
    }

    AfterEach {
        $env:APPDATA = $originalAppData
        $env:LOCALAPPDATA = $originalLocalAppData
    }

    It "finds metadata stored only under LOCALAPPDATA" {
        $syncRoot = New-TestSyncRoot (Join-Path $TestDrive "local-dropbox")
        @{ personal = @{ path = $syncRoot } } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $env:LOCALAPPDATA "Dropbox\info.json")

        Resolve-SyncRoot -SyncProvider Dropbox | Should -Be $syncRoot
    }

    It "selects the only account with both required folders" {
        $syncRoot = New-TestSyncRoot (Join-Path $TestDrive "business-dropbox")
        $personalRoot = Join-Path $TestDrive "personal-dropbox"
        New-Item -ItemType Directory -Path $personalRoot | Out-Null
        @{ personal = @{ path = $personalRoot }; business = @{ path = $syncRoot } } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $env:APPDATA "Dropbox\info.json")

        Resolve-SyncRoot -SyncProvider Dropbox | Should -Be $syncRoot
    }

    It "rejects two matching accounts instead of choosing arbitrarily" {
        $personalRoot = New-TestSyncRoot (Join-Path $TestDrive "personal-matching")
        $businessRoot = New-TestSyncRoot (Join-Path $TestDrive "business-matching")
        @{ personal = @{ path = $personalRoot }; business = @{ path = $businessRoot } } | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $env:APPDATA "Dropbox\info.json")

        { Resolve-SyncRoot -SyncProvider Dropbox } | Should -Throw "*ambiguous*"
    }
}

Describe "SSH include scope" {
    It "repairs a conditional include and stays unchanged on rerun" {
        $userProfile = Join-Path $TestDrive "conditional-profile"
        $sshDirectory = Join-Path $userProfile ".ssh"
        $sshConfig = Join-Path $sshDirectory "config"
        New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
        [IO.File]::WriteAllText($sshConfig, "Host example.com`r`n    User localuser`r`nInclude c:/Apps-data/SSH/config`r`n")

        Set-TestSshConfiguration $userProfile
        $firstRun = [IO.File]::ReadAllText($sshConfig)
        Set-TestSshConfiguration $userProfile

        [IO.File]::ReadAllText($sshConfig) | Should -BeExactly $firstRun
        $firstRun | Should -BeExactly "Host example.com`r`n    User localuser`r`nHost *`r`nInclude c:/Apps-data/SSH/config`r`n"
    }

    It "keeps an existing global include unchanged" {
        $userProfile = Join-Path $TestDrive "global-profile"
        $sshDirectory = Join-Path $userProfile ".ssh"
        $sshConfig = Join-Path $sshDirectory "config"
        New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
        $originalContent = "Include c:/Apps-data/SSH/config`nHost example.com`n    User localuser`n"
        [IO.File]::WriteAllText($sshConfig, $originalContent)

        Set-TestSshConfiguration $userProfile

        [IO.File]::ReadAllText($sshConfig) | Should -BeExactly $originalContent
    }

    It "loads synced hosts after Host and Match blocks while retaining local precedence" -Skip:(-not (Test-Path -LiteralPath "$env:WINDIR\System32\OpenSSH\ssh.exe")) {
        $userProfile = Join-Path $TestDrive "parsed-profile"
        $sshDirectory = Join-Path $userProfile ".ssh"
        $sshConfig = Join-Path $sshDirectory "config"
        $syncedConfig = Join-Path $TestDrive "synced-ssh-config"
        $parserConfig = Join-Path $TestDrive "parser-ssh-config"
        New-Item -ItemType Directory -Path $sshDirectory -Force | Out-Null
        [IO.File]::WriteAllText($sshConfig, "Host local.example`n    User localuser`nMatch host restricted.example`n    Port 2222`nInclude c:/Apps-data/SSH/config`n")
        [IO.File]::WriteAllText($syncedConfig, "Host synced.example`n    HostName 192.0.2.1`n    User synceduser`nHost local.example`n    User overriddenuser`n")
        # OpenSSH rejects included configs writable by other accounts. Isolate
        # this fixture from any permissive ACL inherited from the temp folder.
        $fixtureAcl = Get-Acl -LiteralPath $syncedConfig
        $fixtureAcl.SetAccessRuleProtection($true, $false)
        $fixtureAcl.SetAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.WindowsIdentity]::GetCurrent().User,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.AccessControlType]::Allow
        ))
        Set-Acl -LiteralPath $syncedConfig -AclObject $fixtureAcl
        Set-TestSshConfiguration $userProfile

        # Point only the generated include at a fixture. -G parses locally,
        # without opening connections or reading the real user's SSH config.
        $parserContent = [IO.File]::ReadAllText($sshConfig).Replace('c:/Apps-data/SSH/config', ('"' + $syncedConfig.Replace('\', '/') + '"'))
        [IO.File]::WriteAllText($parserConfig, $parserContent)
        $sshExecutable = Join-Path $env:WINDIR "System32\OpenSSH\ssh.exe"
        $syncedOptions = @(& $sshExecutable -G -T -F $parserConfig synced.example)
        $LASTEXITCODE | Should -Be 0
        $localOptions = @(& $sshExecutable -G -T -F $parserConfig local.example)
        $LASTEXITCODE | Should -Be 0

        $syncedOptions | Should -Contain "hostname 192.0.2.1"
        $syncedOptions | Should -Contain "user synceduser"
        $syncedOptions | Should -Contain "port 22"
        $localOptions | Should -Contain "user localuser"
    }
}

Describe "Sync-backed profile links" {
    It "creates a junction and reuses it on rerun" {
        $target = Join-Path $TestDrive "target"
        $link = Join-Path $TestDrive "link"
        New-Item -ItemType Directory -Path $target | Out-Null
        try {
            & $syncModule {
                param($Link, $Target)
                Set-ProfileLink -LinkPath $Link -TargetPath $Target -Required
                Set-ProfileLink -LinkPath $Link -TargetPath $Target -Required
            } $link $target

            (Get-Item -LiteralPath $link).LinkType | Should -Be "Junction"
            (Get-Item -LiteralPath $link).Target | Should -Contain $target
        }
        finally {
            if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        }
    }

    It "refuses a normal directory and preserves its contents" {
        $target = Join-Path $TestDrive "refusal-target"
        $link = Join-Path $TestDrive "existing-directory"
        New-Item -ItemType Directory -Path $target, $link | Out-Null
        $retainedFile = Join-Path $link "keep.txt"
        Set-Content -LiteralPath $retainedFile -Value "keep"

        {
            & $syncModule {
                param($Link, $Target)
                Set-ProfileLink -LinkPath $Link -TargetPath $Target -Required
            } $link $target
        } | Should -Throw "*already exists and is not a link*"
        Get-Content -LiteralPath $retainedFile | Should -Be "keep"
    }

    It "replaces a junction without deleting either target's contents" {
        $oldTarget = Join-Path $TestDrive "old-target"
        $newTarget = Join-Path $TestDrive "new-target"
        $link = Join-Path $TestDrive "replaced-link"
        New-Item -ItemType Directory -Path $oldTarget, $newTarget | Out-Null
        Set-Content -LiteralPath (Join-Path $oldTarget "old.txt") -Value "old"
        Set-Content -LiteralPath (Join-Path $newTarget "new.txt") -Value "new"
        New-Item -ItemType Junction -Path $link -Target $oldTarget | Out-Null
        try {
            & $syncModule {
                param($Link, $Target)
                Set-ProfileLink -LinkPath $Link -TargetPath $Target -Required
            } $link $newTarget

            Get-Content -LiteralPath (Join-Path $link "new.txt") | Should -Be "new"
            Get-Content -LiteralPath (Join-Path $oldTarget "old.txt") | Should -Be "old"
            (Get-Item -LiteralPath $link).Target | Should -Contain $newTarget
        }
        finally {
            if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
        }
    }

    It "skips a missing optional target without reporting a failure" {
        Mock Write-Warning -ModuleName SyncProfile {}
        & $syncModule {
            param($Root)
            Set-ProfileLink -LinkPath (Join-Path $Root "unused-link") -TargetPath (Join-Path $Root "missing-target")
        } $TestDrive
        Should -Invoke Write-Warning -ModuleName SyncProfile -Times 0 -Exactly
    }
}

Describe "Sync-backed directory copies" {
    BeforeEach {
        $source = Join-Path $TestDrive "copy-source"
        $destination = Join-Path $TestDrive "copy-destination"
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Mock Write-Warning -ModuleName SyncProfile {}
    }

    It "accepts Robocopy success status <Status> and bounds retries" -ForEach @(0..7 | ForEach-Object { @{ Status = $_ } }) {
        $global:SyncProfileTestExitCode = $Status
        Mock robocopy.exe -ModuleName SyncProfile { $global:LASTEXITCODE = $global:SyncProfileTestExitCode }
        try {
            & $syncModule {
                param($Source, $Destination)
                Copy-DirectoryContents -Source $Source -Destination $Destination -Description "fixture"
            } $source $destination

            Should -Invoke Write-Warning -ModuleName SyncProfile -Times 0 -Exactly
            Should -Invoke robocopy.exe -ModuleName SyncProfile -Times 1 -Exactly -ParameterFilter {
                $args -contains '/R:2' -and $args -contains '/W:1'
            }
        }
        finally {
            Remove-Variable -Name SyncProfileTestExitCode -Scope Global
        }
    }

    It "copies real files and accepts native copied and unchanged exit codes" {
        Set-Content -LiteralPath (Join-Path $source "fixture.txt") -Value "fixture"
        $exitCodes = & $syncModule {
            param($Source, $Destination)
            $ErrorActionPreference = "Stop"
            $PSNativeCommandUseErrorActionPreference = $true
            Copy-DirectoryContents -Source $Source -Destination $Destination -Description "fixture"
            $LASTEXITCODE
            Copy-DirectoryContents -Source $Source -Destination $Destination -Description "fixture"
            $LASTEXITCODE
        } $source $destination

        $exitCodes.Count | Should -Be 2
        $exitCodes[0] | Should -Be 1
        $exitCodes[1] | Should -Be 0
        Get-Content -LiteralPath (Join-Path $destination "fixture.txt") | Should -Be "fixture"
        Should -Invoke Write-Warning -ModuleName SyncProfile -Times 0 -Exactly
    }

    It "reports failed copies and retains their diagnostic output" {
        Mock robocopy.exe -ModuleName SyncProfile {
            $global:LASTEXITCODE = 8
            "ERROR 32: fixture file is in use"
        }
        Mock Out-Host -ModuleName SyncProfile {}
        & $syncModule {
            param($Source, $Destination)
            Copy-DirectoryContents -Source $Source -Destination $Destination -Description "fixture"
        } $source $destination

        Should -Invoke Write-Warning -ModuleName SyncProfile -Times 1 -Exactly -ParameterFilter {
            $Message -like '*Robocopy exit code 8*'
        }
        Should -Invoke Out-Host -ModuleName SyncProfile -Times 1 -Exactly -ParameterFilter {
            $InputObject -eq 'ERROR 32: fixture file is in use'
        }
    }
}
