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
echo  7. Reinitialisation / suppression
echo  0. Quitter
echo.
choice /C 12345670 /N /M "Votre choix: "

if errorlevel 8 exit /b 0
if errorlevel 7 goto MAINTENANCE
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

:MAINTENANCE
cls
echo ============================================================
echo              REINITIALISATION / SUPPRESSION
echo ============================================================
echo.
echo  1. Reinitialiser uniquement le Stage metier
echo     Supprime ses conteneurs, volumes et donnees.
echo     Conserve Ubuntu WSL, l'infrastructure, les sources et caches.
echo.
echo  2. Supprimer completement Ubuntu-24.04
echo     Efface definitivement toute la distribution WSL.
echo.
echo  3. Redemarrer uniquement Ubuntu-24.04
echo     Arrete puis relance la distribution utilisee par ORMT.
echo.
echo  0. Retour
echo.
choice /C 1230 /N /M "Votre choix: "
if errorlevel 4 goto MENU
if errorlevel 3 goto RESTART_WSL
if errorlevel 2 goto REMOVE_WSL
if errorlevel 1 goto RESET_STAGE

:RESTART_WSL
cls
echo ============================================================
echo              REDEMARRAGE DE UBUNTU-24.04
echo ============================================================
echo.
echo La distribution ORMT sera arretee puis relancee.
echo Les donnees, conteneurs, volumes et sources seront conserves.
echo.
choice /C ON /N /M "Continuer ? [O/N]: "
if errorlevel 2 goto MAINTENANCE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\windows\setup.ps1" -Mode RestartWsl
set "MAINTENANCE_EXIT=%ERRORLEVEL%"
goto MAINTENANCE_RESULT

:RESET_STAGE
cls
echo ============================================================
echo              ATTENTION - DONNEES STAGE
echo ============================================================
echo.
echo Cette action supprime les bases et fichiers du Stage metier.
echo L'infrastructure partagee et Ubuntu WSL seront conserves.
echo.
set "CONFIRMATION="
set /p "CONFIRMATION=Tape exactement RESET STAGE pour continuer: "
if not "%CONFIRMATION%"=="RESET STAGE" goto MAINTENANCE_CANCELLED
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\windows\setup.ps1" -Mode ResetStage -ConfirmDestructive
set "MAINTENANCE_EXIT=%ERRORLEVEL%"
goto MAINTENANCE_RESULT

:REMOVE_WSL
cls
echo ============================================================
echo           DANGER - SUPPRESSION COMPLETE DE WSL
echo ============================================================
echo.
echo Cette action desinscrit Ubuntu-24.04 et efface definitivement :
echo   - tous les conteneurs, images et volumes Docker ;
echo   - l'infrastructure et toutes les donnees du Stage ;
echo   - les sources, caches et fichiers stockes dans cette distribution.
echo.
echo Les fichiers Windows de ce dossier ne seront pas supprimes.
echo.
set "CONFIRMATION="
set /p "CONFIRMATION=Tape exactement SUPPRIMER WSL pour continuer: "
if not "%CONFIRMATION%"=="SUPPRIMER WSL" goto MAINTENANCE_CANCELLED
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\windows\setup.ps1" -Mode RemoveWsl -ConfirmDestructive
set "MAINTENANCE_EXIT=%ERRORLEVEL%"

:MAINTENANCE_RESULT
echo.
if "%MAINTENANCE_EXIT%"=="0" (
  echo Operation terminee avec succes.
) else (
  echo Operation en echec. Consulte le dernier journal dans logs.
)
echo.
pause
goto MENU

:MAINTENANCE_CANCELLED
echo.
echo Operation annulee : la phrase de confirmation ne correspond pas.
pause
goto MAINTENANCE
