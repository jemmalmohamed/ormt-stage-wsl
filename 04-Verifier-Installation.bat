@echo off
setlocal
chcp 65001 >nul
title ORMT - Diagnostic
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\windows\setup.ps1" -Mode Diagnostic -SourceMode Auto -ProvidedSourcesDir "%~dp0sources"
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%

