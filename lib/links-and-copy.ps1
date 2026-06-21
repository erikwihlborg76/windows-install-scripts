function Test-ReparsePoint {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Get-ReparsePointTarget {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $item = Get-Item -LiteralPath $Path -Force
    $target = @($item.Target) | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($target)) {
        $target = @($item.LinkTarget) | Select-Object -First 1
    }

    return $target
}

function Test-SamePath {
    param(
        [Parameter(Mandatory)]
        [string] $FirstPath,

        [Parameter(Mandatory)]
        [string] $SecondPath
    )

    $firstFullPath = [System.IO.Path]::GetFullPath($FirstPath).TrimEnd('\')
    $secondFullPath = [System.IO.Path]::GetFullPath($SecondPath).TrimEnd('\')

    return [string]::Equals($firstFullPath, $secondFullPath, [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-ReparsePoint {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $item = Get-Item -LiteralPath $Path -Force

    if ($item.PSIsContainer) {
        [System.IO.Directory]::Delete($item.FullName)
    }
    else {
        [System.IO.File]::Delete($item.FullName)
    }
}

function Ensure-Link {
    param(
        [Parameter(Mandatory)]
        [string] $LinkPath,

        [Parameter(Mandatory)]
        [string] $TargetPath,

        [Parameter()]
        [switch] $Required
    )

    if ([string]::IsNullOrWhiteSpace($LinkPath)) {
        if ($Required) {
            throw "Required link path is empty."
        }
        Write-Host "[WARN] Empty link path. Skipping."
        return
    }

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        if ($Required) {
            throw "Required target path is empty for '$LinkPath'."
        }
        Write-Host "[WARN] Empty target path for `"$LinkPath`". Skipping."
        return
    }

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        if ($Required) {
            throw "Required link target does not exist: '$TargetPath'"
        }
        Write-Host "[WARN] Target missing, skipping:"
        Write-Host "  `"$LinkPath`" -> `"$TargetPath`""
        return
    }

    $parent = Split-Path -Parent $LinkPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $LinkPath) {
        if (Test-ReparsePoint -Path $LinkPath) {
            $existingTarget = Get-ReparsePointTarget -Path $LinkPath

            if ($existingTarget -and (Test-SamePath -FirstPath $existingTarget -SecondPath $TargetPath)) {
                Write-Host "[OK] Already linked:"
                Write-Host "  `"$LinkPath`" -> `"$TargetPath`""
                return
            }

            Remove-ReparsePoint -Path $LinkPath
        }
        else {
            if ($Required) {
                throw "Required link path already exists and is not a symlink or junction: '$LinkPath'. Move or rename it, then run the installer again."
            }
            Write-Host "[WARN] Exists and is not a symlink/junction. Skipping:"
            Write-Host "  `"$LinkPath`""
            return
        }
    }

    try {
        $targetItem = Get-Item -LiteralPath $TargetPath -Force

        if ($targetItem.PSIsContainer) {
            New-Item `
                -ItemType Junction `
                -Path $LinkPath `
                -Target $TargetPath `
                -Force | Out-Null
        }
        else {
            New-Item `
                -ItemType SymbolicLink `
                -Path $LinkPath `
                -Target $TargetPath `
                -Force | Out-Null
        }

        Write-Host "[OK] Linked:"
        Write-Host "  `"$LinkPath`" -> `"$TargetPath`""
    }
    catch {
        if ($Required) {
            throw "Failed to create required link '$LinkPath' -> '$TargetPath': $($_.Exception.Message)"
        }
        Write-Host "[WARN] Failed to link:"
        Write-Host "  `"$LinkPath`" -> `"$TargetPath`""
        Write-Host "  $($_.Exception.Message)"
    }
}

function Invoke-RoboCopySafe {
    param(
        [Parameter(Mandatory)]
        [string] $SourceFolder,

        [Parameter(Mandatory)]
        [string] $DestinationFolder
    )

    if ([string]::IsNullOrWhiteSpace($SourceFolder)) {
        Write-Host "[WARN] Empty robocopy source. Skipping."
        return
    }

    if ([string]::IsNullOrWhiteSpace($DestinationFolder)) {
        Write-Host "[WARN] Empty robocopy destination. Skipping."
        return
    }

    if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
        Write-Host "[WARN] Source missing, skipping copy:"
        Write-Host "  `"$SourceFolder`""
        return
    }

    New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null

    & robocopy.exe $SourceFolder $DestinationFolder /E /NFL /NDL /NJH /NJS /NP | Out-Null
    $robocopyExitCode = $LASTEXITCODE

    if ($robocopyExitCode -ge 8) {
        Write-Host "[WARN] Robocopy failed:"
        Write-Host "  `"$SourceFolder`" -> `"$DestinationFolder`""
        Write-Host "  Exit code: $robocopyExitCode"
    }
    else {
        Write-Host "[OK] Copied:"
        Write-Host "  `"$SourceFolder`" -> `"$DestinationFolder`""
    }
}

function Copy-FileIfExists {
    param(
        [Parameter(Mandatory)]
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [string] $DestinationFolder,

        [Parameter(Mandatory)]
        [string] $Description
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-Host "[WARN] Missing ${Description}:"
        Write-Host "`"$SourcePath`""
        return
    }

    New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null

    try {
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationFolder -Force
        Write-Host "[OK] Copied $Description."
    }
    catch {
        Write-Host "[WARN] Failed to copy $Description."
        Write-Host $_.Exception.Message
    }
}
