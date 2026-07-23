param(
  [string]$Distro = "Ubuntu-24.04"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$LogDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("setup-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

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
      $newMode = ($mode -bor $extendedFlags) -band (-bnot $quickEdit) -band (-bnot $insertMode)
      [void][ConsoleMode]::SetConsoleMode($handle, $newMode)
    }
  }
  catch {
    # Si Windows refuse ce réglage, le script continue normalement.
  }
}

Disable-QuickEdit

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "[$(Get-Date -Format HH:mm:ss)] $Message"
  Add-Content -Path $LogFile -Value ""
  Add-Content -Path $LogFile -Value "[$(Get-Date -Format HH:mm:ss)] $Message"
}

function Stop-WithMessage {
  param([string]$Message)
  Write-Host ""
  Write-Error $Message
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
$linuxDir = (& wsl.exe -d $Distro --cd "$scriptDir" -- pwd).Trim()
if (-not $linuxDir) {
  Stop-WithMessage "Impossible de convertir le chemin Windows vers WSL: $scriptDir"
}

Write-Step "Lancement de setup.sh dans $Distro"
Write-Host "Si le mot de passe sudo est demandé, saisis le mot de passe Linux puis appuie sur Entrée."
Write-Host "Le mot de passe ne s'affiche pas pendant la saisie, c'est normal."
$setupExitCode = Invoke-LoggedProcess -FilePath "wsl.exe" -Arguments @(
  "-d", $Distro,
  "--cd", $scriptDir,
  "--",
  "bash", "-lc",
  "chmod +x ./setup.sh ./setup-after-docker-group.sh ./install-wsl-stage.sh ./start-stage.sh ./status-stage.sh ./stop-stage.sh ./reset-stage.sh ./scripts/common.sh 2>/dev/null || true; ./setup.sh"
)

if ($setupExitCode -ne 0) {
  Stop-WithMessage "setup.sh a echoue dans WSL. Regarde le message d'erreur ci-dessus."
}

Write-Host ""
Write-Host "Installation terminee."
Write-Host "Log complet: $LogFile"
