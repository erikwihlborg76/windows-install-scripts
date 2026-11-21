BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psd1") -Force

    function Invoke-BackgroundFixture {
        param([string] $ResourcesRoot)
        InModuleScope SystemSetup -Parameters @{ Resources = $ResourcesRoot } {
            param($Resources)
            Set-RepositoryBackgrounds -ResourcesRoot $Resources
        }
    }
}

Describe "Repository background images" {
    BeforeEach {
        $savedLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path $TestDrive ("profile with spaces " + [guid]::NewGuid().ToString("N"))
        Mock Set-DesktopWallpaper -ModuleName SystemSetup {}
        Mock Set-LockScreenImage -ModuleName SystemSetup {}
        Mock Get-VirtualDesktopTool -ModuleName SystemSetup { "fixture-desktop-cli.exe" }
        Mock Invoke-SetupNativeCommand -ModuleName SystemSetup {
            [pscustomobject] @{ ExitCode = 0; Output = @() }
        }
        Mock Write-Warning -ModuleName SystemSetup {}
    }

    AfterEach { $env:LOCALAPPDATA = $savedLocalAppData }

    It "keeps persistent copies and applies the correct image to all monitors, virtual desktops, and the lock screen" {
        $resources = Join-Path $repositoryRoot "resources"
        InModuleScope SystemSetup -Parameters @{ Resources = $resources } {
            param($Resources)
            Set-RepositoryBackgrounds -ResourcesRoot $Resources
            $wallpaper = Join-Path $env:LOCALAPPDATA "WindowsInstallScripts\Wallpapers\020.jpg"
            $lockScreen = Join-Path $env:LOCALAPPDATA "WindowsInstallScripts\Wallpapers\048.jpg"
            (Get-FileHash -LiteralPath $wallpaper).Hash |
                Should -Be (Get-FileHash -LiteralPath (Join-Path $Resources "Wallpapers\020.jpg")).Hash
            (Get-FileHash -LiteralPath $lockScreen).Hash |
                Should -Be (Get-FileHash -LiteralPath (Join-Path $Resources "Wallpapers\048.jpg")).Hash
            Should -Invoke Set-DesktopWallpaper -Times 1 -Exactly -ParameterFilter { $Path -eq $wallpaper }
            Should -Invoke Set-LockScreenImage -Times 1 -Exactly -ParameterFilter { $Path -eq $lockScreen }
            # The complete wallpaper argument must remain one argument even with spaces.
            Should -Invoke Invoke-SetupNativeCommand -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq "fixture-desktop-cli.exe" -and $Arguments.Count -eq 2 -and
                $Arguments[0] -eq "/Quiet" -and $Arguments[1] -eq "/AllWallpapers:$wallpaper"
            }
            Should -Invoke Write-Warning -Times 0 -Exactly
        }
    }

    It "refreshes persistent images on reruns without accumulating copies" {
        $resources = Join-Path $repositoryRoot "resources"
        Invoke-BackgroundFixture -ResourcesRoot $resources
        $wallpaper = Join-Path $env:LOCALAPPDATA "WindowsInstallScripts\Wallpapers\020.jpg"
        [IO.File]::WriteAllText($wallpaper, "outdated copy")
        Invoke-BackgroundFixture -ResourcesRoot $resources
        (Get-FileHash -LiteralPath $wallpaper).Hash |
            Should -Be (Get-FileHash -LiteralPath (Join-Path $resources "Wallpapers\020.jpg")).Hash
        @(Get-ChildItem -LiteralPath (Split-Path $wallpaper) -File) | Should -HaveCount 2
    }

    It "warns about a virtual-desktop API failure while still setting the lock screen" {
        Mock Invoke-SetupNativeCommand -ModuleName SystemSetup {
            [pscustomobject] @{ ExitCode = -1; Output = @("unsupported shell API") }
        }
        Invoke-BackgroundFixture -ResourcesRoot (Join-Path $repositoryRoot "resources")
        Should -Invoke Write-Warning -ModuleName SystemSetup -Times 1 -Exactly -ParameterFilter {
            $Message -like '*all virtual desktops*unsupported shell API*'
        }
        Should -Invoke Set-DesktopWallpaper -ModuleName SystemSetup -Times 1 -Exactly
        Should -Invoke Set-LockScreenImage -ModuleName SystemSetup -Times 1 -Exactly
    }

    It "still applies monitor and lock-screen images if the desktop tool cannot be obtained" {
        Mock Get-VirtualDesktopTool -ModuleName SystemSetup { throw "download unavailable" }
        Invoke-BackgroundFixture -ResourcesRoot (Join-Path $repositoryRoot "resources")
        Should -Invoke Write-Warning -ModuleName SystemSetup -Times 1 -Exactly -ParameterFilter {
            $Message -like '*all virtual desktops*download unavailable*'
        }
        Should -Invoke Set-DesktopWallpaper -ModuleName SystemSetup -Times 1 -Exactly
        Should -Invoke Set-LockScreenImage -ModuleName SystemSetup -Times 1 -Exactly
    }

    It "attempts the virtual-desktop and lock-screen settings even if the monitor API rejects the change" {
        Mock Set-DesktopWallpaper -ModuleName SystemSetup { throw "organization policy" }
        Invoke-BackgroundFixture -ResourcesRoot (Join-Path $repositoryRoot "resources")
        Should -Invoke Write-Warning -ModuleName SystemSetup -Times 1 -Exactly -ParameterFilter {
            $Message -like '*desktop wallpaper*organization policy*'
        }
        Should -Invoke Invoke-SetupNativeCommand -ModuleName SystemSetup -Times 1 -Exactly
        Should -Invoke Set-LockScreenImage -ModuleName SystemSetup -Times 1 -Exactly
    }

    It "sets the lock screen even if the wallpaper source is missing" {
        Mock Copy-RepositoryBackgroundImage -ModuleName SystemSetup {
            if ($FileName -eq "020.jpg") { throw "missing wallpaper" }
            return "C:\fixture\048.jpg"
        }
        Invoke-BackgroundFixture -ResourcesRoot (Join-Path $repositoryRoot "resources")
        Should -Invoke Write-Warning -ModuleName SystemSetup -Times 1 -Exactly
        Should -Invoke Get-VirtualDesktopTool -ModuleName SystemSetup -Times 0 -Exactly
        Should -Invoke Set-LockScreenImage -ModuleName SystemSetup -Times 1 -Exactly
    }

    It "reports a failed lock-screen API call without undoing the desktop wallpaper" {
        Mock Set-LockScreenImage -ModuleName SystemSetup { throw "lock-screen policy" }
        Invoke-BackgroundFixture -ResourcesRoot (Join-Path $repositoryRoot "resources")
        Should -Invoke Write-Warning -ModuleName SystemSetup -Times 1 -Exactly -ParameterFilter {
            $Message -like '*lock-screen image*lock-screen policy*'
        }
        Should -Invoke Set-DesktopWallpaper -ModuleName SystemSetup -Times 1 -Exactly
        Should -Invoke Invoke-SetupNativeCommand -ModuleName SystemSetup -Times 1 -Exactly
    }
}

Describe "Background integration and Windows API bindings" {
    It "applies backgrounds after desktop creation and policies for <Profile>" -TestCases @(
        @{ Profile = "HOME" }
        @{ Profile = "WORK" }
    ) {
        param($Profile)
        InModuleScope SystemSetup -Parameters @{ Profile = $Profile; Resources = $TestDrive } {
            param($Profile, $Resources)
            $script:fixtureBackgroundPhases = [Collections.Generic.List[string]]::new()
            Mock Assert-Windows11 {}
            Mock Test-SetupAdministrator { $true }
            Mock Set-ComputerBootDescription {}
            Mock Set-WinCultureFromLanguageListOptOut {}
            Mock Set-Culture {}
            Mock Set-ConfiguredRegistryValues {}
            Mock Disable-ConfiguredServices {}
            Mock Disable-ConfiguredScheduledTasks {}
            Mock Disable-SystemSounds {}
            Mock Set-ConfiguredVirtualDesktops { $script:fixtureBackgroundPhases.Add("desktops") }
            Mock Import-LgpoPolicy { $script:fixtureBackgroundPhases.Add("policies") }
            Mock Set-RepositoryBackgrounds { $script:fixtureBackgroundPhases.Add("backgrounds") }
            Mock Disable-NetworkAdapterWake {}
            Mock Disable-WakeTimers {}

            Invoke-SystemConfiguration -Profile $Profile -ResourcesRoot $Resources `
                -CommonConfiguration @{ Registry = @(); ServicesToDisable = @(); ScheduledTasksToDisable = @() } `
                -ProfileConfiguration @{ BootLabel = $Profile; PromptForComputerName = $false; Registry = @(); VirtualDesktopNames = @() }

            @($script:fixtureBackgroundPhases) | Should -Be @("desktops", "policies", "backgrounds")
            Should -Invoke Set-RepositoryBackgrounds -Times 1 -Exactly -ParameterFilter { $ResourcesRoot -eq $Resources }
        }
    }

    It "compiles the repository's desktop API binding without changing the wallpaper" {
        if (-not ("WindowsInstallScripts.DesktopWallpaper" -as [type])) {
            Add-Type -Path (Join-Path $repositoryRoot "modules\SystemSetup\DesktopWallpaper.cs") -ErrorAction Stop
        }
        "WindowsInstallScripts.DesktopWallpaper" -as [type] | Should -Not -BeNullOrEmpty
    }

    It "awaits Windows Runtime results and actions using only an isolated fixture file" {
        InModuleScope SystemSetup -Parameters @{ Root = $TestDrive } {
            param($Root)
            Add-Type -AssemblyName System.Runtime.WindowsRuntime
            $storageFile = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
            $fileIo = [Windows.Storage.FileIO, Windows.Storage, ContentType = WindowsRuntime]
            $path = Join-Path $Root "winrt-async-fixture.txt"
            [IO.File]::WriteAllText($path, "before")
            $file = Wait-SetupWinRtOperation -Operation ($storageFile::GetFileFromPathAsync($path)) -ResultType $storageFile
            $file.Path | Should -Be $path
            Wait-SetupWinRtOperation -Operation ($fileIo::WriteTextAsync($file, "after"))
            [IO.File]::ReadAllText($path) | Should -Be "after"
        }
    }
}
