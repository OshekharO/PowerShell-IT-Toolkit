@echo off
:: ==============================================================================
:: SysAdmin Toolkit - Windows Batch Launcher
:: Automatically elevates to Administrator and runs SysAdmin_Toolkit.ps1
:: ==============================================================================

title SysAdmin Toolkit Launcher

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo [!] Requesting Administrator privileges...
    powershell.exe -Command "Start-Process '%~0' -Verb RunAs"
    goto :eof
)

cd /d "%~dp0"

if exist "%~dp0SysAdmin_Toolkit.ps1" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0SysAdmin_Toolkit.ps1"
) else if exist "%~dp0SysAdmin.ps1" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0SysAdmin.ps1"
) else (
    echo [!] Error: SysAdmin_Toolkit.ps1 not found in %~dp0
    pause
)
