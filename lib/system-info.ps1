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
