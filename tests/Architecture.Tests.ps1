BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $systemModulePath = Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psm1"
}

Describe "Module boundaries" {
    It "keeps sync-backed dependencies out of SystemSetup" {
        $systemText = Get-Content -LiteralPath $systemModulePath -Raw
        foreach ($pattern in @('\$SyncRoot', 'Apps-data', 'OneDrive', 'Dropbox')) {
            $systemText | Should -Not -Match $pattern
        }
    }
}
