@echo off
:: ==============================================================================
:: SysAdmin Toolkit - One-File Cmd Wrapper
:: Automatically elevates to Administrator and launches SysAdmin_Toolkit.ps1
:: ==============================================================================

title SysAdmin Toolkit

net session >nul 2>&1
if %errorLevel% NEQ 0 (
    powershell.exe -Command "Start-Process '%~f0' -Verb RunAs"
    goto :eof
)

cd /d "%~dp0"

if exist "%~dp0SysAdmin_Toolkit.ps1" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0SysAdmin_Toolkit.ps1"
) else (
    echo [!] SysAdmin_Toolkit.ps1 missing.
    pause
)
