@echo off
rem SigmaTweaks launcher.
rem Double-click this to open the interface. Any arguments are passed straight
rem through to SigmaTweaks.ps1, e.g. SigmaTweaks.bat -Preset recommended.
rem
rem The script asks Windows for elevation itself, so there is no need to
rem right-click and choose "Run as administrator" - but it does no harm.

setlocal
cd /d "%~dp0"

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo Windows PowerShell was not found on PATH.
    echo SigmaTweaks needs Windows PowerShell 5.1 or PowerShell 7.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SigmaTweaks.ps1" %*
set "SIGMA_EXIT=%ERRORLEVEL%"

if not "%~1"=="" (
    echo.
    echo SigmaTweaks exited with code %SIGMA_EXIT%.
    pause
)

exit /b %SIGMA_EXIT%
