@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Validate-Package.ps1" >nul
if errorlevel 1 (
  echo Paketpruefung fehlgeschlagen. Fehlerdetails:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Validate-Package.ps1"
  pause
  exit /b 1
)
start "GitHub Manager" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0GitHub-Manager-v4.2.0.ps1"
endlocal