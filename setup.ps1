param(
  [string]$Distro = "Ubuntu-24.04"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$LogDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("setup-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$StartedAt = Get-Date

function Disable-QuickEdit {
  try {
    $signature = @"
using System;
using System.Runtime.InteropServices;

public static class ConsoleMode {
  [DllImport("kernel32.dll")]
  public static extern IntPtr GetStdHandle(int nStdHandle);

  [DllImport("kernel32.dll")]
  public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out int lpMode);

  [DllImport("kernel32.dll")]
  public static extern bool SetConsoleMode(IntPtr hConsoleHandle, int dwMode);
}
"@
    Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue
    $handle = [ConsoleMode]::GetStdHandle(-10)
    $mode = 0
    if ([ConsoleMode]::GetConsoleMode($handle, [ref]$mode)) {
      $quickEdit = 0x0040
      $insertMode = 0x0020
      $extendedFlags = 0x0080
      $virtualTerminalInput = 0x0200
      $newMode = ($mode -bor $extendedFlags) `
        -band (-bnot $quickEdit) `
        -band (-bnot $insertMode) `
        -band (-bnot $virtualTerminalInput)
      [void][ConsoleMode]::SetConsoleMode($handle, $newMode)
    }
  }
  catch {
    # Si Windows refuse ce réglage, le script continue normalement.
  }
}

Disable-QuickEdit

# Désactive aussi les anciens modes de suivi de souris de Windows Terminal.
$escape = [char]27
Write-Host "${escape}[?1000l${escape}[?1002l${escape}[?1003l${escape}[?1006l" -NoNewline
Clear-Host

function Write-Step {
  param([string]$Message)
  $stamp = Get-Date -Format "HH:mm:ss"
  Write-Host ""
  Write-Host "============================================================" -ForegroundColor Cyan
  Write-Host "[$stamp] $Message" -ForegroundColor Cyan
  Write-Host "============================================================" -ForegroundColor Cyan
  Add-Content -Path $LogFile -Value ""
  Add-Content -Path $LogFile -Value "============================================================"
  Add-Content -Path $LogFile -Value "[$stamp] $Message"
  Add-Content -Path $LogFile -Value "============================================================"
}

function Stop-WithMessage {
  param([string]$Message)
  Write-Host ""
  Write-Host "ERREUR: $Message" -ForegroundColor Red
  Add-Content -Path $LogFile -Value "ERREUR: $Message"
  Write-Host ""
  Write-Host "Log complet: $LogFile"
  exit 1
}

function Invoke-LoggedProcess {
  param(
    [string]$FilePath,
    [string[]]$Arguments
  )

  & $FilePath @Arguments 2>&1 | ForEach-Object {
    $line = "$_"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
  }

  return $LASTEXITCODE
}

function Invoke-InteractiveWslSetup {
  param(
    [string]$Distribution,
    [string]$WorkingDirectory,
    [string]$LogFileName
  )

  # Appel direct indispensable : stdin reste relié au terminal pour sudo.
  & wsl.exe -d $Distribution --cd $WorkingDirectory -- `
    bash ./run-wsl-stage.sh $LogFileName

  return $LASTEXITCODE
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
  Stop-WithMessage "WSL n'est pas disponible. Installe WSL puis relance ce script."
}

$distroList = (& wsl.exe -l -q 2>$null) -replace "`0", ""
$hasDistro = $false
foreach ($line in $distroList) {
  if ($line.Trim() -eq $Distro) {
    $hasDistro = $true
    break
  }
}

if (-not $hasDistro) {
  Write-Step "Ubuntu WSL n'est pas encore installe. Installation de $Distro"
  $installExitCode = Invoke-LoggedProcess -FilePath "wsl.exe" -Arguments @("--install", "-d", $Distro)
  if ($installExitCode -ne 0) {
    Stop-WithMessage "L'installation de $Distro a echoue."
  }
  Write-Host ""
  Write-Host "Quand l'installation est terminee, ouvre Ubuntu depuis le menu Demarrer et cree l'utilisateur Linux."
  Write-Host "Ensuite relance depuis PowerShell:"
  Write-Host "  .\setup.bat"
  Write-Host ""
  Write-Host "Log complet: $LogFile"
  exit 0
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Un echec ponctuel de --cd ne signifie pas que la distribution est vierge.
# On teste directement l'utilisateur Linux et on laisse WSL quelques secondes
# pour redemarrer apres une installation ou un arret recent.
$wslReady = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
  $probeOutput = & wsl.exe -d $Distro -- sh -lc "id -u && printf WSL_READY" 2>$null
  if ($LASTEXITCODE -eq 0 -and (($probeOutput | Out-String) -match "WSL_READY")) {
    $wslReady = $true
    break
  }
  Write-Host "WSL ne repond pas encore (tentative $attempt/3)..." -ForegroundColor Yellow
  Start-Sleep -Seconds 2
}

if (-not $wslReady) {
  Write-Step "Premiere initialisation automatique de $Distro"
  Write-Host "Ubuntu va s'ouvrir dans cette fenetre." -ForegroundColor Yellow
  Write-Host "Cree le nom d'utilisateur et le mot de passe Linux si Ubuntu le demande."
  Write-Host "Quand le prompt Linux apparait, tape: exit"
  Write-Host ""

  # Ce lancement interactif declenche l'assistant initial Ubuntu et conserve
  # le clavier pour la creation du compte.
  & wsl.exe -d $Distro

  $probeOutput = & wsl.exe -d $Distro -- sh -lc "id -u && printf WSL_READY" 2>$null
  if ($LASTEXITCODE -ne 0 -or (($probeOutput | Out-String) -notmatch "WSL_READY")) {
    Stop-WithMessage "$Distro n'a pas pu etre initialise automatiquement. Regarde l'erreur WSL affichee ci-dessus."
  }
}

$logFileName = [System.IO.Path]::GetFileName($LogFile)

Write-Step "Lancement de setup.sh dans $Distro"
Write-Host "Journal: $LogFile"
Write-Host "La saisie reste active dans cette fenêtre."
Write-Host "Le script indiquera clairement si le mot de passe Linux est nécessaire."
$setupExitCode = Invoke-InteractiveWslSetup `
  -Distribution $Distro `
  -WorkingDirectory $scriptDir `
  -LogFileName $logFileName

if ($setupExitCode -ne 0) {
  Stop-WithMessage "setup.sh a echoue dans WSL. Regarde le message d'erreur ci-dessus."
}

Write-Host ""
Write-Host "Installation et tests termines avec succes." -ForegroundColor Green
Write-Host ("Duree totale: {0:hh\:mm\:ss}" -f ((Get-Date) - $StartedAt))
Write-Host "Log complet: $LogFile"
