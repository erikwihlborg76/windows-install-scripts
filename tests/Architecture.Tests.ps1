$repositoryRoot = Split-Path -Parent $PSScriptRoot
$systemModulePath = Join-Path $repositoryRoot "modules\SystemSetup\SystemSetup.psm1"
$syncModulePath = Join-Path $repositoryRoot "modules\SyncProfile\SyncProfile.psm1"

Describe "Module boundaries" {
    It "keeps sync-backed dependencies out of SystemSetup" {
        $systemText = Get-Content -LiteralPath $systemModulePath -Raw
        foreach ($pattern in @('\$SyncRoot', 'Apps-data', 'OneDrive', 'Dropbox')) {
            if ($systemText -match $pattern) {
                throw "SystemSetup contains sync-specific pattern: $pattern"
            }
        }
    }

    It "keeps sync-backed behavior in SyncProfile" {
        $syncText = Get-Content -LiteralPath $syncModulePath -Raw
        foreach ($pattern in @('\$SyncRoot', 'Apps-data', 'Resolve-DropboxRoot')) {
            if ($syncText -notmatch $pattern) {
                throw "SyncProfile is missing expected pattern: $pattern"
            }
        }
    }

    It "does not retain the numbered subprocess workflow" {
        $obsoleteFiles = Get-ChildItem `
            -LiteralPath $repositoryRoot `
            -File `
            -Filter "0[1-7]-*.ps1"
        if (@($obsoleteFiles).Count -ne 0) {
            throw "Numbered subprocess scripts are still present."
        }
    }

    It "does not use the removed wrapper state or native configuration commands" {
        $sourceFiles = @(
            Get-Item -LiteralPath (Join-Path $repositoryRoot "00-install.ps1")
            Get-Item -LiteralPath (Join-Path $repositoryRoot "Install.ps1")
            Get-ChildItem `
            -LiteralPath (Join-Path $repositoryRoot "modules") `
            -Recurse `
            -File |
                Where-Object { $_.Extension -in @(".ps1", ".psm1") }
        )

        $sourceText = $sourceFiles |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }

        $combined = $sourceText -join "`n"
        foreach ($pattern in @(
                'Invoke-InstallStep',
                '\$script:Log',
                'reg\.exe\s+add',
                'schtasks\.exe',
                'dism\.exe'
            )) {
            if ($combined -match $pattern) {
                throw "Production code contains obsolete pattern: $pattern"
            }
        }
    }
}
