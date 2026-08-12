$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module `
    (Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psd1") `
    -Force

Describe "SystemSetup public surface" {
    It "exports only the phase-level commands" {
        $expected = @(
            "Assert-WinGet"
            "Install-Applications"
            "Invoke-SystemConfiguration"
            "Remove-UnwantedSoftware"
            "Restart-SetupAsAdministrator"
            "Set-RepositoryApplicationDefaults"
        )

        $actual = @(
            Get-Command -Module SystemSetup |
                Select-Object -ExpandProperty Name |
                Sort-Object
        )

        $differences = @(
            Compare-Object -ReferenceObject ($expected | Sort-Object) -DifferenceObject $actual
        )
        if ($differences.Count -ne 0) {
            throw "SystemSetup exports an unexpected command surface: $($differences | Out-String)"
        }
    }
}

Describe "WinGet prerequisite guard" {
    It "contains the Windows 24H2 IoT recovery instructions" {
        $moduleText = Get-Content `
            -LiteralPath (Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psm1") `
            -Raw

        foreach ($pattern in @(
                'wsreset -i',
                'apps\.microsoft\.com/detail/9nblggh4nns1',
                'Install App Installer'
            )) {
            if ($moduleText -notmatch $pattern) {
                throw "WinGet recovery instructions are missing: $pattern"
            }
        }
    }
}

Describe "Elevation handoff" {
    It "waits for the elevated installer and propagates its exit code" {
        $moduleText = Get-Content `
            -LiteralPath (Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psm1") `
            -Raw
        $installerText = Get-Content `
            -LiteralPath (Join-Path $repositoryRoot "Install.ps1") `
            -Raw

        if ($moduleText -notmatch '(?s)Start-Process.+?-Verb RunAs.+?-Wait.+?-PassThru') {
            throw "The elevation handoff must wait for the elevated child process."
        }
        if ($installerText -notmatch 'exit \$elevatedExitCode') {
            throw "Install.ps1 must propagate the elevated child process exit code."
        }
    }
}
