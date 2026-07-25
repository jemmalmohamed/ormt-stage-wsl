@echo off
setlocal
chcp 65001 >nul
title ORMT - Stage metier
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\windows\setup.ps1" -Mode Stage -SourceMode Auto -ProvidedSourcesDir "%~dp0sources"
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%

