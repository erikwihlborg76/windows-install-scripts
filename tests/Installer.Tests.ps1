BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $fixtureRoot = Join-Path $TestDrive "installer"
    $windowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

    foreach ($directory in @("config", "resources", "modules\SystemSetup", "modules\SyncProfile", "logs")) {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $directory) -Force | Out-Null
    }
    foreach ($file in @(
        "Install.ps1",
        "config\Profiles.psd1",
        "modules\SystemSetup\SystemSetup.psd1",
        "modules\SyncProfile\SyncProfile.psd1"
    )) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot $file) -Destination (Join-Path $fixtureRoot $file)
    }

    # The child process imports only these fixture modules. No Windows setup runs.
    Set-Content -LiteralPath (Join-Path $fixtureRoot "modules\SystemSetup\SystemSetup.psm1") -Value @'
function Invoke-TestPhase {
    param([string] $Name)
    Add-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\phases.txt") -Value $Name
    $scenario = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\scenario.txt")
    if ($scenario -eq "failure" -and $Name -eq "System") { throw "Configuration failed in fixture" }
    if ($scenario -eq "partial" -and $Name -in @("Applications", "Removal")) {
        Write-Warning "$Name failed in fixture"
    }
    if ($scenario -eq "defaults-warning" -and $Name -eq "Defaults") {
        Write-Warning "Application settings failed in fixture"
    }
    if ($Name -eq "Removal" -and $scenario -eq "success") { Write-Host "[SKIP] Already absent" }
}
function Restart-SetupAsAdministrator { param($ScriptPath, $BoundParameters); return $null }
function Assert-WinGet {}
function Install-Applications {
    [CmdletBinding()] param($ConfigRoot, $CommonConfiguration, $ProfileConfiguration)
    Invoke-TestPhase Applications
}
function Set-RepositoryApplicationDefaults {
    [CmdletBinding()] param($ResourcesRoot)
    Invoke-TestPhase Defaults
}
function Set-RepositoryFancyZonesLayout {
    [CmdletBinding()] param($ResourcesRoot)
    Invoke-TestPhase FancyZones
}
function Invoke-SystemConfiguration {
    [CmdletBinding()] param($Profile, $CommonConfiguration, $ProfileConfiguration, $ResourcesRoot)
    Invoke-TestPhase System
}
function Remove-UnwantedSoftware {
    [CmdletBinding()] param($CommonConfiguration, $ProfileConfiguration)
    Invoke-TestPhase Removal
}
'@
    Set-Content -LiteralPath (Join-Path $fixtureRoot "modules\SyncProfile\SyncProfile.psm1") -Value @'
function Resolve-SyncRoot { param($SyncProvider, $SyncRootOverride); return $SyncRootOverride }
function Initialize-SyncedProfile {
    [CmdletBinding()] param($SyncRoot)
    Add-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\phases.txt") -Value "InitializeSync"
}
'@

    function Invoke-InstallerFixture {
        param(
            [string] $Mode = "CONFIGURE_AND_INSTALL",
            [ValidateSet("HOME", "WORK")]
            [string] $Profile = "WORK",
            [string] $Scenario = "success",
            [switch] $SubmitBlankFirst,
            [switch] $SubmitBlankProfileFirst
        )

        Set-Content -LiteralPath (Join-Path $fixtureRoot "scenario.txt") -Value $Scenario
        Set-Content -LiteralPath (Join-Path $fixtureRoot "phases.txt") -Value "" -NoNewline
        $savedTemp = $env:TEMP
        try {
            $env:TEMP = Join-Path $fixtureRoot "logs"
            $choice = switch ($Mode) {
                "CONFIGURE_AND_INSTALL" { "a" }
                "CONFIGURE_ONLY" { "o" }
                "FULL" { "f" }
                default { throw "Unknown fixture selection: $Mode" }
            }
            [string[]] $responses = if ($SubmitBlankFirst) { @("", $choice) } else { @($choice) }
            if ($SubmitBlankProfileFirst) { $responses += "" }
            $responses += $Profile.Substring(0, 1)
            # Answer the real mode and profile prompts; the fixture modules ensure
            # that no Windows changes or application installs can take place.
            $output = @($responses | & $windowsPowerShell -NoLogo -NoProfile -OutputFormat Text -ExecutionPolicy Bypass `
                -File (Join-Path $fixtureRoot "Install.ps1") `
                -SyncProvider OneDrive -SyncRoot $fixtureRoot -SkipConfirmation -NoPause 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $env:TEMP = $savedTemp
        }
        $transcript = Get-ChildItem -LiteralPath (Join-Path $fixtureRoot "logs") -Filter "*.log" |
            Sort-Object Name -Descending | Select-Object -First 1
        [pscustomobject]@{
            ExitCode = $exitCode
            Output = $output -join "`n"
            Phases = @(Get-Content -LiteralPath (Join-Path $fixtureRoot "phases.txt"))
            Transcript = Get-Content -LiteralPath $transcript.FullName -Raw
        }
    }
}

Describe "Installer outcomes" {
    It "runs the expected phases for <Mode> and treats absence as success" -TestCases @(
        @{ Mode = "CONFIGURE_AND_INSTALL"; Expected = "Applications,Defaults,System,FancyZones,Removal" }
        @{ Mode = "CONFIGURE_ONLY"; Expected = "System,Removal" }
        @{ Mode = "FULL"; Expected = "InitializeSync,Applications,Defaults,System,FancyZones,Removal" }
    ) {
        param($Mode, $Expected)
        $result = Invoke-InstallerFixture -Mode $Mode
        $result.ExitCode | Should -Be 0
        ($result.Phases -join ",") | Should -Be $Expected
        $result.Output | Should -Match "Mode:\s+$Mode"
        $result.Transcript | Should -Match '\[OK\] Setup completed\.'
    }

    It "rejects the removed <Parameter> CLI parameter before setup" -TestCases @(
        @{ Parameter = "-Preset"; Value = "FULL" }
        @{ Parameter = "-Mode"; Value = "CONFIGURE_AND_INSTALL" }
        @{ Parameter = "-Profile"; Value = "WORK" }
    ) {
        param($Parameter, $Value)
        $removedArgument = @($Parameter, $Value)
        Set-Content -LiteralPath (Join-Path $fixtureRoot "phases.txt") -Value "" -NoNewline
        $savedErrorAction = $ErrorActionPreference
        try {
            # Windows PowerShell represents native stderr as error records.
            # Collect the expected binding error instead of terminating the test.
            $ErrorActionPreference = "Continue"
            $output = @("a" | & $windowsPowerShell -NoLogo -NoProfile -OutputFormat Text -ExecutionPolicy Bypass `
                -File (Join-Path $fixtureRoot "Install.ps1") @removedArgument `
                -SkipConfirmation -NoPause 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedErrorAction
        }
        $exitCode | Should -Not -Be 0
        ($output -join "`n") | Should -Match 'NamedParameterNotFound'
        @(Get-Content -LiteralPath (Join-Path $fixtureRoot "phases.txt")).Count | Should -Be 0
    }

    It "requires an explicit mode choice even when confirmation is skipped" {
        $result = Invoke-InstallerFixture -Mode CONFIGURE_ONLY -SubmitBlankFirst
        $result.ExitCode | Should -Be 0
        ($result.Phases -join ",") | Should -Be "System,Removal"
        $result.Output | Should -Match 'Mode:\s+CONFIGURE_ONLY'
    }

    It "uses the interactive <Profile> choice when confirmation is skipped" -TestCases @(
        @{ Profile = "HOME" }
        @{ Profile = "WORK" }
    ) {
        param($Profile)
        $result = Invoke-InstallerFixture -Mode CONFIGURE_ONLY -Profile $Profile
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match "Profile:\s+$Profile"
        ($result.Phases -join ",") | Should -Be "System,Removal"
    }

    It "requires an explicit profile choice instead of accepting a blank response" {
        $result = Invoke-InstallerFixture -Mode CONFIGURE_ONLY -Profile WORK -SubmitBlankProfileFirst
        $result.ExitCode | Should -Be 0
        $result.Output | Should -Match 'Profile:\s+WORK'
        ($result.Phases -join ",") | Should -Be "System,Removal"
    }

    It "collects failures across phases and returns partial completion" {
        $result = Invoke-InstallerFixture -Scenario partial
        $result.ExitCode | Should -Be 2
        $result.Output | Should -Match 'Partially complete'
        $result.Output | Should -Match '2 warning\(s\)'
        $result.Transcript | Should -Match 'Applications failed in fixture'
        $result.Transcript | Should -Match 'Removal failed in fixture'
        $result.Transcript | Should -Not -Match '\[OK\] Setup completed\.'
    }

    It "includes repository application settings failures without requiring sync" {
        $result = Invoke-InstallerFixture -Mode CONFIGURE_AND_INSTALL -Scenario defaults-warning
        $result.ExitCode | Should -Be 2
        $result.Output | Should -Match 'Application settings failed in fixture'
    }

    It "stops on a terminating failure and records it in the transcript" {
        $result = Invoke-InstallerFixture -Scenario failure
        $result.ExitCode | Should -Be 1
        $result.Phases | Should -Not -Contain "Removal"
        $result.Transcript | Should -Match 'Configuration failed in fixture'
        $result.Output | Should -Not -Match '\[OK\] Setup completed\.'
    }
}
