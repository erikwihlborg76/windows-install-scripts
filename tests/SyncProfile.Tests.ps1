$repositoryRoot = Split-Path -Parent $PSScriptRoot
Import-Module `
    (Join-Path $repositoryRoot "modules\SyncProfile\SyncProfile.psd1") `
    -Force

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
