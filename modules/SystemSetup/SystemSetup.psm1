. (Join-Path $PSScriptRoot "ApplicationSettings.ps1")

function Test-SetupAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-SetupAsAdministrator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ScriptPath,

        [Parameter()]
        [System.Collections.IDictionary] $BoundParameters = @{}
    )

    if (Test-SetupAdministrator) {
        return $null
    }

    # Encode the invocation so spaces, quotes, and trailing path separators
    # survive the Windows command-line parser without custom escaping rules.
    $invocation = "& '{0}'" -f $ScriptPath.Replace("'", "''")

    foreach ($parameter in ($BoundParameters.GetEnumerator() | Sort-Object Key)) {
        if ($parameter.Value -is [Management.Automation.SwitchParameter]) {
            if ($parameter.Value.IsPresent) {
                $invocation += " -$($parameter.Key)"
            }
            continue
        }

        $value = [string] $parameter.Value
        $invocation += " -{0} '{1}'" -f $parameter.Key, $value.Replace("'", "''")
    }

    $invocation += '; exit $LASTEXITCODE'
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($invocation))

    $process = Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand" `
        -Verb RunAs `
        -Wait `
        -PassThru

    return [int] $process.ExitCode
}

function Invoke-SetupNativeCommand {
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter()]
        [string[]] $Arguments = @()
    )

    $command = Get-Command -Name $FilePath -CommandType Application -ErrorAction Stop |
        Select-Object -First 1

    # Windows PowerShell 5.1 wraps redirected stderr in NativeCommandError
    # records. Diagnostics on stderr do not determine a native tool's success.
    $ErrorActionPreference = "Continue"
    $PSNativeCommandUseErrorActionPreference = $false
    # Native commands update the global automatic variable, even in a module.
    $global:LASTEXITCODE = $null
    $output = @(& $command.Source @Arguments 2>&1)
    $exitCode = $global:LASTEXITCODE
    if ($null -eq $exitCode) {
        throw "Could not start native command '$FilePath': $($output -join [Environment]::NewLine)"
    }

    return [pscustomobject] @{
        ExitCode = [int] $exitCode
        Output = @($output | ForEach-Object { $_.ToString() })
    }
}

function Get-WinGetInstallInstructions {
    return @"
WinGet is required but is not installed or could not be started.

On Windows 24H2 IoT:
1. Run this command to enable Microsoft Store:
   wsreset -i
2. Open this page:
   https://apps.microsoft.com/detail/9nblggh4nns1?hl=en-US&gl=EN
3. Install App Installer, then run this installer again.
"@
}

function Test-WinGetAvailable {
    $wingetCommand = Get-Command `
        -Name "winget.exe" `
        -CommandType Application `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $wingetCommand) {
        return $false
    }

    try {
        $result = Invoke-SetupNativeCommand -FilePath $wingetCommand.Source -Arguments @("--version")
        return ($result.ExitCode -eq 0)
    }
    catch {
        return $false
    }
}

function Assert-WinGet {
    [CmdletBinding()]
    param()

    if (-not (Test-WinGetAvailable)) {
        throw (Get-WinGetInstallInstructions)
    }
}

function Install-WinGetManifest {
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "WinGet package manifest was not found: $ManifestPath"
    }

    Write-Host ""
    Write-Host "Importing WinGet packages from: $ManifestPath"

    $result = Invoke-SetupNativeCommand -FilePath "winget.exe" -Arguments @(
        "import", "--import-file", $ManifestPath,
        "--ignore-versions", "--accept-package-agreements",
        "--accept-source-agreements", "--disable-interactivity"
    )

    foreach ($line in $result.Output) {
        Write-Host $line
    }

    if ($result.ExitCode -ne 0) {
        throw "WinGet package import failed with exit code $($result.ExitCode): $ManifestPath"
    }

    Write-Host "[OK] WinGet package import completed."
}

function Test-WindowsActivation {
    $slmgr = Join-Path $env:WINDIR "System32\slmgr.vbs"

    $result = Invoke-SetupNativeCommand -FilePath "cscript.exe" -Arguments @("//Nologo", $slmgr, "/xpr")
    foreach ($line in $result.Output) {
        Write-Host $line
    }
    if ($result.ExitCode -ne 0) {
        Write-Warning "Could not check Windows activation status."
        return
    }

    Write-Host ""
    Write-Host "To trigger legitimate online activation, use:"
    Write-Host "  cscript.exe //Nologo `"$slmgr`" /ato"
    Write-Host ""
    Write-Host "For Microsoft 365 / Office, sign in with the licensed Microsoft account."
}

function Install-Applications {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ConfigRoot,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $CommonConfiguration,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ProfileConfiguration
    )

    Assert-WinGet

    Write-Host ""
    Write-Host "========== Installing applications =========="

    $manifestNames = @($CommonConfiguration.PackageManifest) +
        @($ProfileConfiguration.AdditionalPackageManifests)

    $manifestPaths = foreach ($manifestName in $manifestNames) {
        if ($manifestName -isnot [string] -or [string]::IsNullOrWhiteSpace($manifestName)) {
            throw "Invalid WinGet package manifest name: '$manifestName'. Expected a nonempty string."
        }

        $manifestPath = Join-Path $ConfigRoot $manifestName
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "WinGet package manifest was not found: $manifestPath"
        }
        $manifestPath
    }

    foreach ($manifestPath in $manifestPaths) {
        Install-WinGetManifest -ManifestPath $manifestPath
    }

    Write-Host ""
    Write-Host "========== Windows activation check =========="
    Test-WindowsActivation
}

function Set-RepositoryApplicationDefaults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ResourcesRoot
    )

    Write-Host ""
    Write-Host "========== Repository-provided application settings =========="

    Set-RepositoryApplicationSettings -ResourcesRoot $ResourcesRoot

    $terminalSettings = Join-Path $ResourcesRoot "Windows Terminal\settings.json"
    if (-not (Test-Path -LiteralPath $terminalSettings -PathType Leaf)) {
        Write-Warning "Missing Windows Terminal settings: $terminalSettings"
        return
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA "Packages"
    $terminalPackages = @(
        Get-ChildItem `
            -LiteralPath $packagesRoot `
            -Directory `
            -Filter "Microsoft.WindowsTerminal_*" `
            -ErrorAction SilentlyContinue
    )

    if ($terminalPackages.Count -eq 0) {
        Write-Warning "No Microsoft.WindowsTerminal package folder was found."
        return
    }

    foreach ($package in $terminalPackages) {
        $localState = Join-Path $package.FullName "LocalState"
        $destination = Join-Path $localState "settings.json"

        try {
            New-Item -ItemType Directory -Path $localState -Force -ErrorAction Stop | Out-Null
            Copy-Item `
                -LiteralPath $terminalSettings `
                -Destination $destination `
                -Force `
                -ErrorAction Stop
            Write-Host "[OK] Copied Windows Terminal settings to $destination"
        }
        catch {
            Write-Warning "Failed to copy Windows Terminal settings to '$destination': $($_.Exception.Message)"
        }
    }
}

function Get-WindowsDisplayName {
    $productName = $null

    try {
        $productName = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption
    }
    catch {
        # Fall back to the registry when CIM is unavailable.
    }

    if ([string]::IsNullOrWhiteSpace($productName)) {
        $currentVersion = Get-ItemProperty `
            -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" `
            -ErrorAction Stop

        $productName = [string] $currentVersion.ProductName
        if ([string]::IsNullOrWhiteSpace($productName)) {
            throw "Could not determine the installed Windows edition."
        }

        $buildNumber = 0
        [void][int]::TryParse([string] $currentVersion.CurrentBuildNumber, [ref] $buildNumber)

        if (($currentVersion.InstallationType -eq "Client") -and ($buildNumber -ge 22000)) {
            $productName = $productName -replace "^Windows 10", "Windows 11"
        }
    }

    $productName = ($productName -replace "^Microsoft\s+", "").Trim()
    foreach ($familyPattern in @("Windows Server \d{4}", "Windows 11", "Windows 10")) {
        if ($productName -match $familyPattern) {
            return $Matches[0]
        }
    }

    return $productName
}

function Set-ConfiguredRegistryValues {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Settings
    )

    foreach ($setting in $Settings) {
        try {
            if (-not (Test-Path -LiteralPath $setting.Path -ErrorAction Stop)) {
                New-Item -Path $setting.Path -Force -ErrorAction Stop | Out-Null
            }

            $valueName = if ([string]::IsNullOrEmpty([string] $setting.Name)) {
                "(Default)"
            }
            else {
                $setting.Name
            }
            New-ItemProperty `
                -LiteralPath $setting.Path `
                -Name $valueName `
                -PropertyType $setting.Type `
                -Value $setting.Value `
                -Force `
                -ErrorAction Stop |
                Out-Null
        }
        catch {
            $valueName = if ([string]::IsNullOrEmpty([string] $setting.Name)) {
                "(Default)"
            }
            else {
                $setting.Name
            }
            throw "Failed to set registry value '$($setting.Path)\$valueName': $($_.Exception.Message)"
        }
    }

    Write-Host "[OK] Applied $($Settings.Count) registry settings."
}

function Disable-ConfiguredServices {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Names
    )

    try {
        $services = @(Get-Service -ErrorAction Stop)
    }
    catch {
        Write-Warning "Failed to query services: $($_.Exception.Message)"
        return
    }

    foreach ($name in $Names) {
        $service = $services | Where-Object { $_.Name -eq $name }
        if (-not $service) {
            Write-Host "[SKIP] Service not found: $name"
            continue
        }

        try {
            Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
            Write-Host "[OK] Disabled service: $name"
        }
        catch {
            Write-Warning "Failed to disable service '$name': $($_.Exception.Message)"
        }
    }
}

function Disable-ConfiguredScheduledTasks {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Tasks
    )

    try {
        $scheduledTasks = @(Get-ScheduledTask -ErrorAction Stop)
    }
    catch {
        Write-Warning "Failed to query scheduled tasks: $($_.Exception.Message)"
        return
    }

    foreach ($taskDefinition in $Tasks) {
        $task = $scheduledTasks | Where-Object {
            $_.TaskPath -eq $taskDefinition.TaskPath -and $_.TaskName -eq $taskDefinition.TaskName
        }

        $qualifiedName = "$($taskDefinition.TaskPath)$($taskDefinition.TaskName)"
        if (-not $task) {
            Write-Host "[SKIP] Scheduled task not found: $qualifiedName"
            continue
        }

        try {
            $task | Disable-ScheduledTask -ErrorAction Stop | Out-Null
            Write-Host "[OK] Disabled scheduled task: $qualifiedName"
        }
        catch {
            Write-Warning "Failed to disable scheduled task '$qualifiedName': $($_.Exception.Message)"
        }
    }
}

function Disable-SystemSounds {
    try {
        Get-ChildItem -LiteralPath "HKCU:\AppEvents\Schemes\Apps" -Recurse -ErrorAction Stop |
            Where-Object { $_.PSChildName -eq ".Current" } |
            ForEach-Object {
                Set-Item -LiteralPath $_.PSPath -Value "" -ErrorAction Stop
            }
        Write-Host "[OK] Disabled configured system sounds."
    }
    catch {
        Write-Warning "Failed to disable one or more system sounds: $($_.Exception.Message)"
    }
}

function Set-ComputerBootDescription {
    param(
        [Parameter(Mandatory)]
        [string] $BootLabel
    )

    $windowsName = Get-WindowsDisplayName
    $description = "$windowsName $BootLabel"

    Write-Host "Detected operating system: $windowsName"
    Write-Host "Setting boot menu entry to: `"$description`""

    $result = Invoke-SetupNativeCommand -FilePath "bcdedit.exe" -Arguments @(
        "/set", "{current}", "description", $description
    )
    foreach ($line in $result.Output) {
        Write-Host $line
    }
    if ($result.ExitCode -ne 0) {
        Write-Warning "Failed to update the boot entry description with BCDEdit."
        return
    }

    Write-Host "[OK] Updated boot entry description."
}

function Request-ComputerRename {
    Write-Host ""
    Write-Host "Type the new computer name, or leave empty to skip."
    Write-Host "Example: GIGABYTE-Z690"
    $newComputerName = Read-Host ">"

    if ([string]::IsNullOrWhiteSpace($newComputerName)) {
        Write-Host "[SKIP] Computer rename skipped."
        return
    }

    try {
        Rename-Computer -NewName $newComputerName -Force -ErrorAction Stop
        Write-Host "[OK] Computer rename requested. A reboot is required."
    }
    catch {
        Write-Warning "Failed to rename computer: $($_.Exception.Message)"
    }
}

function Disable-NetworkAdapterWake {
    Write-Host ""
    Write-Host "========== Network wake =========="

    try {
        $networkDevices = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        Get-NetAdapter -Physical -IncludeHidden -ErrorAction Stop |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.InterfaceDescription) } |
            ForEach-Object { [void] $networkDevices.Add($_.InterfaceDescription.Trim()) }
    }
    catch {
        Write-Warning "Failed to query physical network adapters: $($_.Exception.Message)"
        return
    }

    $result = Invoke-SetupNativeCommand -FilePath "powercfg.exe" -Arguments @("-devicequery", "wake_armed")
    $wakeArmedDevices = @(
        $result.Output |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ine "NONE" }
    )
    if ($result.ExitCode -ne 0) {
        Write-Warning "Failed to query wake-armed devices."
        return
    }

    $networkWakeDevices = @(
        $wakeArmedDevices | Where-Object { $networkDevices.Contains($_) }
    )

    if ($networkWakeDevices.Count -eq 0) {
        Write-Host "[OK] No wake-armed network devices found."
        return
    }

    $disabledCount = 0
    foreach ($device in $networkWakeDevices) {
        $result = Invoke-SetupNativeCommand -FilePath "powercfg.exe" -Arguments @("-devicedisablewake", $device)
        if ($result.ExitCode -ne 0) {
            Write-Warning "Failed to disable network wake on '$device'."
            continue
        }

        $disabledCount++
        Write-Host "[OK] Disabled network wake on: $device"
    }

    Write-Host "Disabled wake on $disabledCount of $($networkWakeDevices.Count) network devices."
}

function Disable-WakeTimers {
    Write-Host ""
    Write-Host "========== Wake timers =========="

    foreach ($powerMode in @("AC", "DC")) {
        $result = Invoke-SetupNativeCommand -FilePath "powercfg.exe" -Arguments @(
            "/SET${powerMode}VALUEINDEX", "SCHEME_CURRENT", "SUB_SLEEP", "RTCWAKE", "0"
        )
        if ($result.ExitCode -ne 0) {
            Write-Warning "Failed to disable $powerMode wake timers."
        }
        else {
            Write-Host "[OK] Disabled $powerMode wake timers."
        }
    }

    $result = Invoke-SetupNativeCommand -FilePath "powercfg.exe" -Arguments @("/SETACTIVE", "SCHEME_CURRENT")
    if ($result.ExitCode -ne 0) {
        Write-Warning "Failed to re-apply the current power scheme."
    }
    else {
        Write-Host "[OK] Re-applied the current power scheme."
    }
}

function Get-LgpoExecutablePath {
    $command = Get-Command -Name "LGPO.exe" -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    $candidates = @(
        if ($command) { $command.Source }
        if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\LGPO.exe" }
        if ($env:ProgramFiles) { Join-Path $env:ProgramFiles "WinGet\Links\LGPO.exe" }
    )

    $match = $candidates |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            (Test-Path -LiteralPath $_ -PathType Leaf)
        } |
        Select-Object -First 1

    if ($match) {
        return $match
    }

    $packageRoots = @(
        if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages" }
        if ($env:ProgramFiles) { Join-Path $env:ProgramFiles "WinGet\Packages" }
    )

    foreach ($packageRoot in $packageRoots) {
        if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
            continue
        }

        $match = Get-ChildItem `
            -LiteralPath $packageRoot `
            -Directory `
            -Filter "Microsoft.SecurityComplianceToolkit.LGPO_*" `
            -ErrorAction SilentlyContinue |
            ForEach-Object {
                Get-ChildItem `
                    -LiteralPath $_.FullName `
                    -Filter "LGPO.exe" `
                    -File `
                    -Recurse `
                    -ErrorAction SilentlyContinue
            } |
            Select-Object -ExpandProperty FullName -First 1

        if ($match) {
            return $match
        }
    }

    return $null
}

function Install-LgpoIfMissing {
    $lgpoExecutable = Get-LgpoExecutablePath
    if ($lgpoExecutable) {
        return $lgpoExecutable
    }

    Write-Host "LGPO.exe was not found. Installing it with WinGet..."
    Assert-WinGet

    $result = Invoke-SetupNativeCommand -FilePath "winget.exe" -Arguments @(
        "install", "--id", "Microsoft.SecurityComplianceToolkit.LGPO", "--source", "winget",
        "--exact", "--silent", "--accept-package-agreements",
        "--accept-source-agreements", "--disable-interactivity"
    )

    foreach ($line in $result.Output) {
        Write-Host $line
    }

    $lgpoExecutable = Get-LgpoExecutablePath
    if (-not $lgpoExecutable) {
        throw "LGPO.exe was not found after the automatic WinGet installation attempt (exit code $($result.ExitCode))."
    }

    return $lgpoExecutable
}

function Import-LgpoPolicy {
    param(
        [Parameter(Mandatory)]
        [string] $ResourcesRoot
    )

    Write-Host ""
    Write-Host "========== Local Group Policy =========="

    $policyPath = Join-Path $ResourcesRoot "LGPO\global_policy_objects.txt"
    if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) {
        throw "LGPO policy file was not found: $policyPath"
    }

    $lgpoExecutable = Install-LgpoIfMissing
    $result = Invoke-SetupNativeCommand -FilePath $lgpoExecutable -Arguments @("/t", $policyPath)

    foreach ($line in $result.Output) {
        Write-Host $line
    }

    if ($result.ExitCode -ne 0) {
        throw "LGPO policy import failed with exit code $($result.ExitCode)."
    }

    Write-Host "[OK] Local Group Policy import completed."
}

function Invoke-SystemConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("HOME", "WORK")]
        [string] $Profile,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $CommonConfiguration,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ProfileConfiguration,

        [Parameter(Mandatory)]
        [string] $ResourcesRoot
    )

    if (-not (Test-SetupAdministrator)) {
        throw "System configuration must run as Administrator."
    }

    Write-Host ""
    Write-Host "========== Configuring Windows =========="
    Write-Host "Profile: $Profile"

    Set-ComputerBootDescription -BootLabel $ProfileConfiguration.BootLabel

    if ($ProfileConfiguration.PromptForComputerName) {
        Request-ComputerRename
    }

    try {
        Set-WinCultureFromLanguageListOptOut -OptOut $true
        Set-Culture -CultureInfo "sv-SE"
        Write-Host "[OK] Applied Swedish regional settings."
    }
    catch {
        Write-Warning "Failed to set Swedish regional settings: $($_.Exception.Message)"
    }

    $registrySettings = @($CommonConfiguration.Registry) + @($ProfileConfiguration.Registry)
    Set-ConfiguredRegistryValues -Settings $registrySettings
    Disable-ConfiguredServices -Names @($CommonConfiguration.ServicesToDisable)
    Disable-ConfiguredScheduledTasks -Tasks @($CommonConfiguration.ScheduledTasksToDisable)
    Disable-SystemSounds

    if ($ProfileConfiguration.DisableLastAccess) {
        $result = Invoke-SetupNativeCommand -FilePath "fsutil.exe" -Arguments @(
            "behavior", "set", "DisableLastAccess", "1"
        )
        foreach ($line in $result.Output) {
            Write-Host $line
        }
        if ($result.ExitCode -ne 0) {
            Write-Warning "Failed to disable last-access timestamp updates."
        }
        else {
            Write-Host "[OK] Disabled last-access timestamp updates."
        }
    }

    Import-LgpoPolicy -ResourcesRoot $ResourcesRoot
    Disable-NetworkAdapterWake
    Disable-WakeTimers
}

function Remove-AppxPattern {
    param(
        [Parameter(Mandatory)]
        [string] $Pattern,

        [Parameter(Mandatory)]
        [string] $Label
    )

    $found = $false
    $queryFailed = $false

    $installedPackages = @()
    try {
        $installedPackages = @(Get-AppxPackage -AllUsers -Name $Pattern -ErrorAction Stop)
    }
    catch {
        $queryFailed = $true
        Write-Warning "Failed to query installed AppX packages for '$Label': $($_.Exception.Message)"
    }
    foreach ($package in $installedPackages) {
        $found = $true
        try {
            Remove-AppxPackage `
                -Package $package.PackageFullName `
                -AllUsers `
                -ErrorAction Stop
            Write-Host "[OK] Removed installed AppX package: $($package.PackageFullName)"
        }
        catch {
            Write-Warning "Failed to remove installed AppX package '$($package.PackageFullName)': $($_.Exception.Message)"
        }
    }

    $provisionedPackages = @()
    try {
        $provisionedPackages = @(
            Get-AppxProvisionedPackage -Online -ErrorAction Stop |
                Where-Object { $_.DisplayName -like $Pattern }
        )
    }
    catch {
        $queryFailed = $true
        Write-Warning "Failed to query provisioned AppX packages for '$Label': $($_.Exception.Message)"
    }
    foreach ($package in $provisionedPackages) {
        $found = $true
        try {
            Remove-AppxProvisionedPackage `
                -Online `
                -PackageName $package.PackageName `
                -ErrorAction Stop |
                Out-Null
            Write-Host "[OK] Removed provisioned AppX package: $($package.PackageName)"
        }
        catch {
            Write-Warning "Failed to remove provisioned AppX package '$($package.PackageName)': $($_.Exception.Message)"
        }
    }

    if (-not $found -and -not $queryFailed) {
        Write-Host "[SKIP] AppX package not found: $Label"
    }
}

function Uninstall-WinGetName {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    Write-Host "Removing WinGet package by name: $Name"
    $result = Invoke-SetupNativeCommand -FilePath "winget.exe" -Arguments @(
        "uninstall", "--name", $Name, "--exact", "--silent",
        "--accept-source-agreements", "--disable-interactivity"
    )

    foreach ($line in $result.Output) {
        Write-Host $line
    }

    # APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND (0x8A150014).
    # https://github.com/microsoft/winget-cli/blob/master/src/AppInstallerSharedLib/Public/AppInstallerErrors.h
    if ($result.ExitCode -eq -1978335212) {
        Write-Host "[SKIP] WinGet package is not installed: $Name"
    }
    elseif ($result.ExitCode -ne 0) {
        Write-Warning "Could not uninstall '$Name' with WinGet; exit code $($result.ExitCode)."
    }
    else {
        Write-Host "[OK] WinGet uninstall completed: $Name"
    }
}

function Remove-ConfiguredCapability {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Label
    )

    try {
        $capability = Get-WindowsCapability -Online -Name $Name -ErrorAction Stop
        if (-not $capability -or $capability.State -ne "Installed") {
            Write-Host "[SKIP] Windows capability is not installed: $Label"
            return
        }

        Remove-WindowsCapability -Online -Name $Name -ErrorAction Stop | Out-Null
        Write-Host "[OK] Removed Windows capability: $Label"
    }
    catch {
        Write-Warning "Failed to remove Windows capability '$Label': $($_.Exception.Message)"
    }
}

function Remove-UnwantedSoftware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $CommonConfiguration,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ProfileConfiguration
    )

    Assert-WinGet

    Write-Host ""
    Write-Host "========== Removing unwanted software =========="

    foreach ($removal in $CommonConfiguration.AppxRemovals) {
        Remove-AppxPattern -Pattern $removal.Pattern -Label $removal.Label
    }

    $wingetNames = @($CommonConfiguration.WingetNameRemovals) +
        @($ProfileConfiguration.AdditionalWingetNameRemovals)
    foreach ($name in $wingetNames) {
        Uninstall-WinGetName -Name $name
    }

    foreach ($capability in $CommonConfiguration.CapabilitiesToRemove) {
        Remove-ConfiguredCapability -Name $capability.Name -Label $capability.Label
    }
}

Export-ModuleMember -Function @(
    "Assert-WinGet"
    "Install-Applications"
    "Invoke-SystemConfiguration"
    "Remove-UnwantedSoftware"
    "Restart-SetupAsAdministrator"
    "Set-RepositoryApplicationDefaults"
)
