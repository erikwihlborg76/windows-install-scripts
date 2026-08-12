@echo off
setlocal

rem Run from the installer directory even when launched from Explorer.
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
set "ExitCode=%ERRORLEVEL%"

endlocal & exit /b %ExitCode%
