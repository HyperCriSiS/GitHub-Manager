@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Validate-Package.ps1"
if errorlevel 1 (
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0GitHub-Manager-v4.2.0.ps1"
endlocal
