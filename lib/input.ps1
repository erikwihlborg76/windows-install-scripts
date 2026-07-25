function Read-Choice {
    param(
        [Parameter(Mandatory)]
        [string] $Prompt,

        [Parameter(Mandatory)]
        [string[]] $AllowedValues
    )

    while ($true) {
        $value = Read-Host $Prompt

        if ($value -in $AllowedValues) {
            return $value
        }

        Write-Host "Invalid choice. Enter one of: $($AllowedValues -join ', ')"
    }
}

function Select-InstallMode {
    Write-Host ""
    Write-Host "========== Select workflow =========="
    Write-Host "  [1] Full install"
    Write-Host "      Uses the sync root and installs applications."
    Write-Host "  [2] Tweaks and app removal only"
    Write-Host "      Does not use the sync root or install applications."
    Write-Host ""

    $choice = Read-Choice -Prompt "Enter choice (1-2)" -AllowedValues @("1", "2")

    switch ($choice) {
        "1" { return "FULL" }
        "2" { return "TWEAKS_AND_REMOVAL" }
    }
}

function Select-InstallTarget {
    Write-Host ""
    Write-Host "========== Select target =========="
    Write-Host "  [1] HOME"
    Write-Host "  [2] WORK"
    Write-Host ""

    $choice = Read-Choice -Prompt "Enter choice (1-2)" -AllowedValues @("1", "2")

    switch ($choice) {
        "1" { return "HOME" }
        "2" { return "WORK" }
    }
}

function Confirm-TweaksAndRemoval {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("HOME", "WORK")]
        [string] $Target
    )

    Write-Host ""
    Write-Host "Target selected: $Target"
    Write-Host "Workflow: Tweaks and app removal only"
    Write-Host ""
    Write-Host "This workflow will:"
    Write-Host "  - Apply sync-root-independent Windows tweaks."
    Write-Host "  - Remove the apps configured in 07-remove-apps.ps1."
    Write-Host ""
    Write-Host "It will not select a sync root, create sync links, restore private settings,"
    Write-Host "or install applications."
    Write-Host ""

    $answer = Read-Choice `
        -Prompt "Continue? (Y/N)" `
        -AllowedValues @("Y", "y", "N", "n")

    return ($answer -match "^[Yy]$")
}
