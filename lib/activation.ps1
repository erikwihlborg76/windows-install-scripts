function Check-WindowsActivation {
    # Legitimate activation/status check only.
    # This does not bypass activation.

    $slmgr = Join-Path $env:WINDIR "System32\slmgr.vbs"

    & cscript.exe //Nologo $slmgr /xpr

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARN] Could not check Windows activation status."
        return
    }

    Write-Host ""
    Write-Host "To trigger legitimate online activation, use:"
    Write-Host "  cscript.exe //Nologo `"$slmgr`" /ato"
    Write-Host ""
    Write-Host "For Microsoft 365 / Office, sign in with the licensed Microsoft account."
}
