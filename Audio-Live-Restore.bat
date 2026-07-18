@echo off
chcp 65001 >nul
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%Audio-Live.ps1"
set "LAUNCHER=%~f0"
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

title Session Audio - Restauration

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Demande des droits administrateur...
  "%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:LAUNCHER -WorkingDirectory $env:SCRIPT_DIR -Verb RunAs"
  exit /b
)

echo Restauration de la session audio...
echo.

"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Restore

exit /b %errorlevel%
