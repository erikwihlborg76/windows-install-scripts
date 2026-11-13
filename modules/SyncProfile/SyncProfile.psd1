@{
    RootModule = "SyncProfile.psm1"
    ModuleVersion = "1.0.0"
    GUID = "06461794-b81d-4e4d-87b0-dfa9f0da5f7b"
    Author = "windows-install-scripts"
    Description = "Sync-provider discovery and sync-backed profile restoration."
    PowerShellVersion = "5.1"
    FunctionsToExport = @(
        "Initialize-SyncedProfile"
        "Resolve-SyncRoot"
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
