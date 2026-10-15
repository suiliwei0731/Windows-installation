@echo off
setlocal EnableExtensions
title InstallKit - Post-System Setup

rem ============================================================
rem  InstallKit one-click launcher (run after clean Windows install)
rem  Usage: double-click this file after the OS is installed.
rem  Flow : elevate -> check resources -> confirm -> install
rem         network driver -> runtimes -> tools, one by one.
rem  Notes: this file is ASCII-only on purpose (avoids codepage
rem         issues); Chinese messages come from the PowerShell
rem         scripts, which are UTF-8 with BOM.
rem ============================================================

rem -- Locate library root by the marker file config\settings.json (no hard-coded drive letter)
set "KIT=%~dp0"
if exist "%KIT%config\settings.json" goto :root_found
if exist "%KIT%InstallKit\config\settings.json" ( set "KIT=%KIT%InstallKit\" & goto :root_found )

echo [ERROR] Cannot find InstallKit root (missing config\settings.json).
echo         Please place this file at the InstallKit library root.
pause
exit /b 1

:root_found
set "KIT=%KIT:~0,-1%"

rem -- Require administrator rights; re-launch elevated if needed
net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting administrator privileges...
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
cd /d "%KIT%"

echo ============================================================
echo   InstallKit - post-install environment setup
echo   Library root: %KIT%
echo ============================================================
echo.

echo [Step 1/2] Checking resource completeness (read-only, no changes)...
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%KIT%\06_Scripts\Initialize-InstallKit.ps1" -Root "%KIT%" -DryRun
if errorlevel 1 (
    echo.
    echo [WARN] Resource check did not complete normally. See messages above and logs in 07_Logs.
    echo        If any critical package is missing, fix it before continuing.
    echo.
    pause
)

echo.
echo [Step 2/2] Installing in order (network driver -^> runtimes -^> tools, one at a time)...
echo           You will be asked to type YES to confirm.
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%KIT%\06_Scripts\Start-Setup.ps1" -Root "%KIT%" -Execute -Force -InstallDrivers

echo.
echo ============================================================
echo   Done. Logs: 07_Logs  ^| Reports: 09_Reports
echo ============================================================
pause
endlocal
exit /b 0
