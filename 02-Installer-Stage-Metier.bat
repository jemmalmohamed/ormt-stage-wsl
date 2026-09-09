@echo off
setlocal
chcp 65001 >nul
title ORMT - Stage metier
set "PROVIDED_SOURCES_DIR=%~1"
if not defined PROVIDED_SOURCES_DIR set "PROVIDED_SOURCES_DIR=%~dp0sources"

:ACTION
cls
echo ============================================================
echo              ACTION STAGE METIER
echo ============================================================
echo.
echo  1. DEPLOYER       - Mettre a jour sans importer les donnees
echo  2. INITIALISER    - Importer init-data sans supprimer les donnees
echo  3. REINITIALISER  - Supprimer les donnees puis tout initialiser
echo  4. PREMIERE INSTALLATION - Socle et vrais administrateurs, sans donnees metier
echo  0. Annuler
echo.
set "ACTION_CHOICE="
set /p "ACTION_CHOICE=Votre choix puis Entree: "
if "%ACTION_CHOICE%"=="0" exit /b 0
if "%ACTION_CHOICE%"=="1" set "STAGE_ACTION=Deploy"
if "%ACTION_CHOICE%"=="2" set "STAGE_ACTION=Initialize"
if "%ACTION_CHOICE%"=="3" set "STAGE_ACTION=Reinitialize"
if "%ACTION_CHOICE%"=="4" set "STAGE_ACTION=FirstInstallation"
if not defined STAGE_ACTION goto ACTION

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\windows\setup.ps1" -Mode Stage -StageAction "%STAGE_ACTION%" -SourceMode Auto -ProvidedSourcesDir "%PROVIDED_SOURCES_DIR%"
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%
