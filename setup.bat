@echo off
title ORMT Stage WSL Setup
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
echo.
echo Fin du script. Appuyez sur une touche pour fermer cette fenetre.
pause >nul
exit /b %ERRORLEVEL%
