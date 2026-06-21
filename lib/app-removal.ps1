function Uninstall-Name {
    param(
        [Parameter(Mandatory)]
        [string] $AppName
    )

    if ([string]::IsNullOrWhiteSpace($AppName)) {
        Write-Warn "Empty app name. Skipping."
        return
    }

    Write-Host "[UNINSTALL] $AppName"

    Write-LogLine ""
    Write-LogLine "============================================================"
    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Uninstall by name: $AppName"
    Write-LogLine "============================================================"

    & winget uninstall `
        --name $AppName `
        --silent `
        --accept-source-agreements `
        1>> $script:Log 2>&1

    $rc = $LASTEXITCODE

    if ($rc -eq 0) {
        Write-Ok "Removed or uninstall completed: $AppName"
    }
    else {
        Write-Warn "Could not uninstall by name: $AppName ; exit code $rc"
        Invoke-WinGetErrorLookup -ExitCode $rc
    }
}

function Remove-AppxPackageName {
    param(
        [Parameter(Mandatory)]
        [string] $PackageName,

        [Parameter()]
        [string] $PackageLabel = $PackageName
    )

    if ([string]::IsNullOrWhiteSpace($PackageName)) {
        Write-Warn "Empty AppX package name. Skipping."
        return
    }

    if ([string]::IsNullOrWhiteSpace($PackageLabel)) {
        $PackageLabel = $PackageName
    }

    Write-Host "[APPX] Removing $PackageLabel ($PackageName)"

    Write-LogLine ""
    Write-LogLine "============================================================"
    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Remove AppX package pattern: $PackageLabel ($PackageName)"
    Write-LogLine "============================================================"

    $removedAny = $false
    $removeErrors = @()

    $packages = Get-AppxPackage -AllUsers -Name $PackageName -ErrorAction SilentlyContinue

    foreach ($pkg in $packages) {
        $removedAny = $true
        Write-Host "Removing installed package: $($pkg.PackageFullName)"
        Write-LogLine "Removing installed package: $($pkg.PackageFullName)"

        Remove-AppxPackage `
            -Package $pkg.PackageFullName `
            -AllUsers `
            -ErrorAction Continue `
            -ErrorVariable +removeErrors `
            1>> $script:Log 2>&1
    }

    $provisionedPackages = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object DisplayName -like $PackageName

    foreach ($pkg in $provisionedPackages) {
        $removedAny = $true
        Write-Host "Removing provisioned package: $($pkg.PackageName)"
        Write-LogLine "Removing provisioned package: $($pkg.PackageName)"

        Remove-AppxProvisionedPackage `
            -Online `
            -PackageName $pkg.PackageName `
            -ErrorAction Continue `
            -ErrorVariable +removeErrors `
            1>> $script:Log 2>&1
    }

    if ($removeErrors.Count -gt 0) {
        Write-Warn "Could not remove one or more AppX package entries for $PackageLabel."
        foreach ($removeError in $removeErrors) {
            Write-LogLine "[WARN] $removeError"
        }
        return
    }

    if ($removedAny) {
        Write-Ok "Removed AppX package or operation completed: $PackageLabel"
    }
    else {
        Write-Info "AppX package not found, skipping: $PackageLabel"
    }
}

function Remove-Capability {
    param(
        [Parameter(Mandatory)]
        [string] $CapabilityName,

        [Parameter()]
        [string] $CapabilityLabel = $CapabilityName
    )

    if ([string]::IsNullOrWhiteSpace($CapabilityName)) {
        Write-Warn "Empty capability name. Skipping."
        return
    }

    if ([string]::IsNullOrWhiteSpace($CapabilityLabel)) {
        $CapabilityLabel = $CapabilityName
    }

    Write-Host "[DISM] Removing $CapabilityLabel"

    Write-LogLine ""
    Write-LogLine "============================================================"
    Write-LogLine "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Remove capability: $CapabilityLabel ($CapabilityName)"
    Write-LogLine "============================================================"

    & dism.exe /Online /Remove-Capability /CapabilityName:$CapabilityName 1>> $script:Log 2>&1

    $rc = $LASTEXITCODE

    if ($rc -eq 0) {
        Write-Ok "Removed capability or operation completed: $CapabilityLabel"
    }
    else {
        Write-Warn "Could not remove capability: $CapabilityLabel ; exit code $rc"
    }
}
