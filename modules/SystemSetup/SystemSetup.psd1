@{
    RootModule = "SystemSetup.psm1"
    ModuleVersion = "1.0.0"
    GUID = "4f6d6ed9-b517-4fb7-a976-a4c235c47a02"
    Author = "windows-install-scripts"
    Description = "Sync-independent Windows provisioning operations."
    PowerShellVersion = "5.1"
    FunctionsToExport = @(
        "Assert-WinGet"
        "Install-Applications"
        "Invoke-SystemConfiguration"
        "Remove-UnwantedSoftware"
        "Restart-SetupAsAdministrator"
        "Set-RepositoryApplicationDefaults"
        "Set-RepositoryFancyZonesLayout"
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
