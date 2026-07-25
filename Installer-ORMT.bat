@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Installation ORMT Stage

:MENU
cls
echo ============================================================
echo              INSTALLATION ORMT STAGE
echo ============================================================
echo.
echo  1. Installation complete recommandee
echo  2. Infrastructure uniquement
echo  3. Stage metier uniquement
echo  4. Verifier l'installation
echo  5. Reparer ou reprendre
echo  6. Configuration
echo  0. Quitter
echo.
choice /C 1234560 /N /M "Votre choix: "

if errorlevel 7 exit /b 0
if errorlevel 6 goto CONFIGURATION
if errorlevel 5 goto MODE_REPAIR
if errorlevel 4 goto MODE_DIAGNOSTIC
if errorlevel 3 goto MODE_STAGE
if errorlevel 2 goto MODE_INFRASTRUCTURE
if errorlevel 1 goto MODE_FULL

:MODE_REPAIR
set "INSTALL_MODE=Repair"
goto SOURCE_MENU

:MODE_DIAGNOSTIC
set "INSTALL_MODE=Diagnostic"
set "SOURCE_MODE=Auto"
set "PROVIDED_DIR=%~dp0sources"
goto RUN

:MODE_STAGE
set "INSTALL_MODE=Stage"
goto SOURCE_MENU

:MODE_INFRASTRUCTURE
set "INSTALL_MODE=Infrastructure"
goto SOURCE_MENU

:MODE_FULL
set "INSTALL_MODE=Full"
goto SOURCE_MENU

:SOURCE_MENU
cls
echo ============================================================
echo              PROVENANCE DES PROJETS
echo ============================================================
echo.
echo  1. Utiliser les dossiers fournis
echo  2. Cloner ou mettre a jour depuis Git
echo  3. Detection automatique
echo  0. Retour
echo.
choice /C 1230 /N /M "Votre choix: "
if errorlevel 4 goto MENU
if errorlevel 3 goto SOURCE_AUTO
if errorlevel 2 goto SOURCE_GIT
if errorlevel 1 goto PROVIDED_PATH

:SOURCE_AUTO
set "SOURCE_MODE=Auto"
set "PROVIDED_DIR=%~dp0sources"
goto RUN

:SOURCE_GIT
set "SOURCE_MODE=Git"
set "PROVIDED_DIR=%~dp0sources"
goto RUN

:PROVIDED_PATH
set "PROVIDED_DIR=%~dp0sources"
set "CUSTOM_DIR="
echo.
echo Dossier par defaut:
echo   %PROVIDED_DIR%
set /p "CUSTOM_DIR=Appuie sur Entree ou saisis un autre dossier: "
if defined CUSTOM_DIR set "PROVIDED_DIR=%CUSTOM_DIR%"
set "SOURCE_MODE=Provided"

:RUN
cls
echo Mode       : %INSTALL_MODE%
echo Sources    : %SOURCE_MODE%
if not "%SOURCE_MODE%"=="Git" if defined PROVIDED_DIR echo Dossier     : %PROVIDED_DIR%
echo.
choice /C ON /N /M "Continuer ? [O/N]: "
if errorlevel 2 goto MENU

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\windows\setup.ps1" -Mode "%INSTALL_MODE%" -SourceMode "%SOURCE_MODE%" -ProvidedSourcesDir "%PROVIDED_DIR%"
set "INSTALL_EXIT=%ERRORLEVEL%"
echo.
if "%INSTALL_EXIT%"=="0" (
  echo Installation terminee avec succes.
) else (
  echo Installation en echec. Consulte le dernier journal dans logs.
)
echo.
pause
goto MENU

:CONFIGURATION
if not exist "%~dp0config\.env" copy /Y "%~dp0config\.env.example" "%~dp0config\.env" >nul
start "" notepad.exe "%~dp0config\.env"
echo.
echo Enregistre le fichier puis relance l'installation.
pause
goto MENU
