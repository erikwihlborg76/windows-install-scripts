function Copy-RepositoryBackgroundImage {
    param(
        [Parameter(Mandatory)]
        [string] $ResourcesRoot,

        [Parameter(Mandatory)]
        [string] $FileName
    )

    $source = Join-Path $ResourcesRoot "Wallpapers\$FileName"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Repository background image was not found: '$source'."
    }
    # The bootstrap removes its downloaded repository after setup exits.
    $destinationRoot = Join-Path $env:LOCALAPPDATA "WindowsInstallScripts\Wallpapers"
    New-Item -ItemType Directory -Path $destinationRoot -Force -ErrorAction Stop | Out-Null
    $destination = Join-Path $destinationRoot $FileName
    Copy-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop
    return $destination
}

function Set-DesktopWallpaper {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not ("WindowsInstallScripts.DesktopWallpaper" -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot "DesktopWallpaper.cs") -ErrorAction Stop
    }
    [WindowsInstallScripts.DesktopWallpaper]::Set($Path)
}

function Wait-SetupWinRtOperation {
    param(
        [Parameter(Mandatory)]
        [object] $Operation,

        [type] $ResultType
    )

    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and
        $(if ($ResultType) {
            $_.IsGenericMethod -and $_.GetGenericArguments().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        }
        else {
            -not $_.IsGenericMethod -and
            $_.GetParameters()[0].ParameterType.FullName -eq "Windows.Foundation.IAsyncAction"
        })
    } | Select-Object -First 1
    if (-not $method) { throw "Could not find the Windows Runtime async bridge." }
    if ($ResultType) { $method = $method.MakeGenericMethod($ResultType) }
    $task = $method.Invoke($null, @($Operation))
    if (-not $task.Wait([TimeSpan]::FromSeconds(30))) {
        throw "The Windows background-image operation timed out."
    }
    return $task.GetAwaiter().GetResult()
}

function Set-LockScreenImage {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
    $storageFile = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
    $lockScreen = [Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime]
    $image = Wait-SetupWinRtOperation -Operation ($storageFile::GetFileFromPathAsync($Path)) -ResultType $storageFile
    Wait-SetupWinRtOperation -Operation ($lockScreen::SetImageFileAsync($image))
}

function Set-RepositoryBackgrounds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ResourcesRoot
    )

    $wallpaper = $null
    try {
        $wallpaper = Copy-RepositoryBackgroundImage -ResourcesRoot $ResourcesRoot -FileName "020.jpg"
        Set-DesktopWallpaper -Path $wallpaper
        Write-Host "[OK] Applied 020.jpg as the wallpaper on all monitors."
    }
    catch {
        Write-Warning "Failed to set the desktop wallpaper: $($_.Exception.Message)"
    }

    if ($wallpaper) {
        try {
            $desktopCli = Get-VirtualDesktopTool
            $result = Invoke-SetupNativeCommand -FilePath $desktopCli -Arguments @("/Quiet", "/AllWallpapers:$wallpaper")
            # /AllWallpapers leaves the CLI pipeline at zero on success.
            if ($result.ExitCode -ne 0) {
                throw "VirtualDesktop CLI failed (exit $($result.ExitCode)): $($result.Output -join ' ')"
            }
            Write-Host "[OK] Applied 020.jpg to all virtual desktops."
        }
        catch {
            Write-Warning "Failed to set the wallpaper on all virtual desktops: $($_.Exception.Message)"
        }
    }

    try {
        $lockScreen = Copy-RepositoryBackgroundImage -ResourcesRoot $ResourcesRoot -FileName "048.jpg"
        Set-LockScreenImage -Path $lockScreen
        Write-Host "[OK] Applied 048.jpg as the current user's lock-screen image."
    }
    catch {
        Write-Warning "Failed to set the lock-screen image: $($_.Exception.Message)"
    }
}
