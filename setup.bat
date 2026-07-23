@echo off
setlocal EnableExtensions
title ORMT Stage WSL Setup
chcp 65001 >nul
cls
echo ============================================================
echo   ORMT STAGE - INSTALLATION WSL
echo ============================================================
echo.
echo Les logs sont affiches en direct et conserves dans:
echo   %~dp0logs
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
set "SETUP_EXIT_CODE=%ERRORLEVEL%"
echo.
if "%SETUP_EXIT_CODE%"=="0" (
  echo ============================================================
  echo   SUCCES - installation et tests termines
  echo ============================================================
) else (
  echo ============================================================
  echo   ECHEC - code %SETUP_EXIT_CODE%
  echo   Consultez le dernier fichier dans %~dp0logs
  echo ============================================================
)
echo.
echo Appuyez sur une touche pour fermer cette fenetre.
pause >nul
exit /b %SETUP_EXIT_CODE%
