@echo off
cd /d "%~dp0"
echo Uruchamiam Uruchom.ps1 ...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uruchom.ps1"
echo.
pause
