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
function Restore-SyncedApplicationState {
    [CmdletBinding()] param($SyncRoot)
    Add-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\phases.txt") -Value "RestoreSync"
    if ((Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\scenario.txt")) -eq "sync-warning") {
        Write-Warning "Sync restoration failed in fixture"
    }
}
'@

    function Invoke-InstallerFixture {
        param([string] $Preset = "FULL", [string] $Scenario = "success")

        Set-Content -LiteralPath (Join-Path $fixtureRoot "scenario.txt") -Value $Scenario
        Set-Content -LiteralPath (Join-Path $fixtureRoot "phases.txt") -Value "" -NoNewline
        $savedTemp = $env:TEMP
        try {
            $env:TEMP = Join-Path $fixtureRoot "logs"
            $output = @(& $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass `
                -File (Join-Path $fixtureRoot "Install.ps1") -Profile WORK -Preset $Preset `
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
    It "runs the expected phases for <Preset> and treats absence as success" -TestCases @(
        @{ Preset = "FULL"; Expected = "InitializeSync,Applications,Defaults,RestoreSync,System,Removal" }
        @{ Preset = "SYSTEM_AND_APPS"; Expected = "Applications,Defaults,System,Removal" }
        @{ Preset = "SYSTEM_ONLY"; Expected = "System,Removal" }
    ) {
        param($Preset, $Expected)
        $result = Invoke-InstallerFixture -Preset $Preset
        $result.ExitCode | Should -Be 0
        ($result.Phases -join ",") | Should -Be $Expected
        $result.Transcript | Should -Match '\[OK\] Setup completed\.'
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

    It "includes failures from the sync module in the outcome" {
        $result = Invoke-InstallerFixture -Scenario sync-warning
        $result.ExitCode | Should -Be 2
        $result.Output | Should -Match 'Sync restoration failed in fixture'
    }

    It "stops on a terminating failure and records it in the transcript" {
        $result = Invoke-InstallerFixture -Scenario failure
        $result.ExitCode | Should -Be 1
        $result.Phases | Should -Not -Contain "Removal"
        $result.Transcript | Should -Match 'Configuration failed in fixture'
        $result.Output | Should -Not -Match '\[OK\] Setup completed\.'
    }
}
