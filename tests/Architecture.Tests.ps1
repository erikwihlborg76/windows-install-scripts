BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $systemModulePath = Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psm1"
}

Describe "Module boundaries" {
    It "keeps sync-backed dependencies out of SystemSetup" {
        $systemText = (Get-Content -LiteralPath $systemModulePath -Raw) +
            (Get-Content -LiteralPath (Join-Path $repositoryRoot "modules\SystemSetup\ApplicationSettings.ps1") -Raw) +
            (Get-Content -LiteralPath (Join-Path $repositoryRoot "modules\SystemSetup\VirtualDesktops.ps1") -Raw) +
            (Get-Content -LiteralPath (Join-Path $repositoryRoot "modules\SystemSetup\FancyZonesSettings.ps1") -Raw)
        foreach ($pattern in @('\$SyncRoot', 'Apps-data', 'OneDrive', 'Dropbox')) {
            $systemText | Should -Not -Match $pattern
        }
    }
}
