@echo off
setlocal
set "PREVIEW=%~dp0winui\bin\x64\Release\net8.0-windows10.0.19041.0\win-x64\Oathgate.exe"
if exist "%PREVIEW%" goto launch
:build
(
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-WinUI.ps1"
  if errorlevel 1 (
    echo SteamNite build failed.
    pause
    exit /b 1
  )
)
:launch
start "" "%PREVIEW%"
