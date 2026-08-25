@echo off
setlocal
chcp 65001 >nul
title ORMT - Stage metier

:ACTION
cls
echo ============================================================
echo              ACTION STAGE METIER
echo ============================================================
echo.
echo  1. DEPLOYER       - Mettre a jour sans importer les donnees
echo  2. INITIALISER    - Importer init-data sans supprimer les donnees
echo  3. REINITIALISER  - Supprimer les donnees puis tout initialiser
echo  0. Annuler
echo.
set "ACTION_CHOICE="
set /p "ACTION_CHOICE=Votre choix puis Entree: "
if "%ACTION_CHOICE%"=="0" exit /b 0
if "%ACTION_CHOICE%"=="1" set "STAGE_ACTION=Deploy"
if "%ACTION_CHOICE%"=="2" set "STAGE_ACTION=Initialize"
if "%ACTION_CHOICE%"=="3" set "STAGE_ACTION=Reinitialize"
if not defined STAGE_ACTION goto ACTION

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\windows\setup.ps1" -Mode Stage -StageAction "%STAGE_ACTION%" -SourceMode Auto -ProvidedSourcesDir "%~dp0sources"
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%
