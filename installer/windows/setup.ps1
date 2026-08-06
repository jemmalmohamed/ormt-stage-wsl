param(
  [ValidateSet("Full", "Infrastructure", "Stage", "Diagnostic", "Repair", "ResetStage", "RemoveWsl", "RestartWsl")]
  [string]$Mode = "Full",

  [ValidateSet("Auto", "Provided", "Git")]
  [string]$SourceMode = "Auto",

  [string]$ProvidedSourcesDir = "",
  [string]$Distro = "Ubuntu-24.04",

  [switch]$SelectGitBranches,

  [switch]$ConfirmDestructive,

  [ValidateSet("Ask", "Always", "Never")]
  [string]$FinalWslRestart = "Ask"
)

$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$PackageRoot = [System.IO.Path]::GetFullPath(
  (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..")
)
$LogDir = Join-Path $PackageRoot "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir ("setup-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$StartedAt = Get-Date
$ReinstallStage = ($Mode -eq "Stage")
$LocalDomainsScript = Join-Path $PSScriptRoot "configure-local-domains.ps1"

if ([string]::IsNullOrWhiteSpace($ProvidedSourcesDir)) {
  $ProvidedSourcesDir = Join-Path $PackageRoot "sources"
}
elseif (-not [System.IO.Path]::IsPathRooted($ProvidedSourcesDir)) {
  $ProvidedSourcesDir = Join-Path $PackageRoot $ProvidedSourcesDir
}
$ProvidedSourcesDir = [System.IO.Path]::GetFullPath($ProvidedSourcesDir)

function Write-Step {
  param([string]$Message)
  $stamp = Get-Date -Format "HH:mm:ss"
  $lines = @(
    "",
    "============================================================",
    "[$stamp] $Message",
    "============================================================"
  )
  foreach ($line in $lines) {
    Write-Host $line -ForegroundColor Cyan
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
  }
}

function Stop-WithMessage {
  param([string]$Message)
  Write-Host ""
  Write-Host "ERREUR: $Message" -ForegroundColor Red
  Add-Content -LiteralPath $LogFile -Value "ERREUR: $Message" -Encoding UTF8
  Write-Host "Journal: $LogFile"
  exit 1
}

function Test-WslReady {
  & wsl.exe -d $Distro -- sh -lc "id -u >/dev/null" 2>$null | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Wait-WslReady {
  for ($attempt = 1; $attempt -le 8; $attempt++) {
    if (Test-WslReady) {
      return $true
    }
    Write-Host "Demarrage de WSL ($attempt/8)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
  }
  return $false
}

function Set-DefaultWslDistribution {
  Write-Step "Sélection de $Distro comme distribution WSL par défaut"
  Add-Content -LiteralPath $LogFile -Value "Exécution: wsl.exe --set-default $Distro" -Encoding UTF8
  & wsl.exe --set-default $Distro
  if ($LASTEXITCODE -ne 0) {
    Stop-WithMessage "Impossible de définir $Distro comme distribution WSL par défaut."
  }
}

function Convert-ToWslPath {
  param([string]$WindowsPath)

  $fullPath = [System.IO.Path]::GetFullPath($WindowsPath)
  $windowsRoot = [System.IO.Path]::GetPathRoot($fullPath)

  if ($windowsRoot -notmatch "^(?<drive>[A-Za-z]):\\$") {
    Stop-WithMessage "Chemin Windows non pris en charge par WSL: $fullPath. Place le dossier ORMT sur un disque local (C:, D:, etc.)."
  }

  $drive = $Matches["drive"].ToLowerInvariant()
  $relativePath = $fullPath.Substring($windowsRoot.Length).Replace("\", "/")

  if ([string]::IsNullOrWhiteSpace($relativePath)) {
    return "/mnt/$drive"
  }

  return "/mnt/$drive/$relativePath"
}

function Invoke-WslInstaller {
  param(
    [string]$WslLogFile,
    [string]$WslProvidedSources
  )

  $resetStageArgs = @()
  if ($ReinstallStage) {
    $resetStageArgs = @("--reset-stage")
  }

  $branchSelectionArgs = @()
  if ($SelectGitBranches) {
    $branchSelectionArgs = @("--select-git-branches")
  }

  & wsl.exe -d $Distro --cd $PackageRoot -- `
    bash ./installer/wsl/setup.sh `
      --mode $Mode `
      --source-mode $SourceMode `
      --log-file $WslLogFile `
      --provided-sources-dir $WslProvidedSources `
      @branchSelectionArgs `
      @resetStageArgs

  # Ne pas retourner la sortie standard dans une affectation PowerShell : elle
  # doit rester directement reliee au terminal pour sudo. Seul le code est
  # enregistre separement afin d'eviter la fausse erreur historique.
  $script:WslInstallerExitCode = $LASTEXITCODE
}

function Restart-WslDistribution {
  param([string]$Reason)
  Write-Step "Redemarrage de WSL - $Reason"
  $runningDistros = @(& wsl.exe --list --running --quiet 2>$null) |
    ForEach-Object { ($_ -replace "`0", "").Trim() } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  if ($Distro -in $runningDistros) {
    Add-Content -LiteralPath $LogFile -Value "Execution: wsl.exe --terminate $Distro" -Encoding UTF8
    & wsl.exe --terminate $Distro
    if ($LASTEXITCODE -ne 0) {
      Stop-WithMessage "Impossible d'arreter la distribution $Distro."
    }
  }
  else {
    Add-Content -LiteralPath $LogFile -Value "$Distro était déjà arrêtée; démarrage direct." -Encoding UTF8
  }

  Start-Sleep -Seconds 3
  if (-not (Wait-WslReady)) {
    Stop-WithMessage "$Distro ne redemarre pas apres son arret."
  }
}

function Invoke-ColdStartValidation {
  param(
    [ValidateSet("auto", "infrastructure", "stage")]
    [string]$Scope,
    [string]$WslLogFile
  )

  Write-Step "Validation des services apres redemarrage WSL"
  & wsl.exe -d $Distro --cd $PackageRoot -- `
    bash ./installer/wsl/tests/test-after-restart.sh `
      --scope $Scope `
      --log-file $WslLogFile
  if ($LASTEXITCODE -ne 0) {
    Stop-WithMessage "Les services ORMT ne fonctionnent pas correctement apres le redemarrage WSL."
  }
}

function Test-InteractiveInput {
  try {
    return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
  }
  catch {
    return $false
  }
}

function Test-FinalWslRestartRequested {
  switch ($FinalWslRestart) {
    "Always" { return $true }
    "Never" { return $false }
    "Ask" {
      if (-not (Test-InteractiveInput)) {
        $message = "Entrée non interactive détectée: redémarrage final WSL ignoré."
        Write-Host $message -ForegroundColor Yellow
        Add-Content -LiteralPath $LogFile -Value $message -Encoding UTF8
        return $false
      }

      Write-Host ""
      $answer = Read-Host "Redémarrer WSL et vérifier le démarrage à froid ? [o/N]"
      return ($answer -match "^(?i:o|oui|y|yes)$")
    }
  }
}

$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslCommand) {
  Stop-WithMessage "WSL n'est pas disponible sur ce PC."
}

if ($Mode -ne "RemoveWsl") {
  Write-Step "Configuration des domaines locaux ORMT"
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LocalDomainsScript
  if ($LASTEXITCODE -ne 0) {
    Stop-WithMessage "Impossible de configurer les domaines *.ormt.local dans le fichier hosts Windows."
  }
}

if ($Mode -eq "RemoveWsl") {
  if (-not $ConfirmDestructive) {
    Stop-WithMessage "La suppression complète exige le paramètre -ConfirmDestructive."
  }

  $installedDistros = @(& wsl.exe --list --quiet 2>$null) |
    ForEach-Object { ($_ -replace "`0", "").Trim() } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if ($Distro -notin $installedDistros) {
    Stop-WithMessage "La distribution $Distro n'est pas installée."
  }

  Write-Step "Suppression complète de la distribution WSL $Distro"
  Add-Content -LiteralPath $LogFile -Value "Exécution: wsl.exe --unregister $Distro" -Encoding UTF8
  & wsl.exe --unregister $Distro
  if ($LASTEXITCODE -ne 0) {
    Stop-WithMessage "La suppression de la distribution $Distro a échoué."
  }

  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $LocalDomainsScript -Remove
  if ($LASTEXITCODE -ne 0) {
    Stop-WithMessage "Ubuntu a été supprimé, mais le nettoyage des domaines ORMT locaux a échoué."
  }

  Write-Host ""
  Write-Host "La distribution $Distro et toutes ses données ont été supprimées." -ForegroundColor Green
  Write-Host "Relance l'installation complète pour repartir de zéro." -ForegroundColor Green
  Write-Host "Journal: $LogFile"
  exit 0
}

if ($Mode -eq "RestartWsl") {
  $installedDistros = @(& wsl.exe --list --quiet 2>$null) |
    ForEach-Object { ($_ -replace "`0", "").Trim() } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if ($Distro -notin $installedDistros) {
    Stop-WithMessage "La distribution $Distro n'est pas installée."
  }

  Restart-WslDistribution -Reason "redémarrage manuel demandé pour l'installation ORMT"
  $restartWslLogFile = Convert-ToWslPath -WindowsPath $LogFile
  Invoke-ColdStartValidation -Scope "auto" -WslLogFile $restartWslLogFile
  Write-Host ""
  Write-Host "La distribution $Distro a redémarré et les services installés sont validés." -ForegroundColor Green
  Write-Host "Journal: $LogFile"
  exit 0
}

$hasDistro = Test-WslReady

if (-not $hasDistro) {
  if ($Mode -in @("Diagnostic", "ResetStage")) {
    Stop-WithMessage "$Distro n'est pas installée; le mode $Mode n'est pas possible."
  }
  Write-Step "Installation de $Distro"
  & wsl.exe --install -d $Distro
  if ($LASTEXITCODE -ne 0) {
    Stop-WithMessage "L'installation de $Distro a echoue."
  }
  Write-Host ""
  Write-Host "Redemarre Windows si demande, ouvre Ubuntu une fois pour creer l'utilisateur Linux, puis relance le meme BAT." -ForegroundColor Yellow
  Write-Host "Journal: $LogFile"
  exit 0
}

if (-not (Wait-WslReady)) {
  Write-Step "Initialisation interactive de $Distro"
  Write-Host "Cree l'utilisateur et le mot de passe Linux, puis tape exit."
  & wsl.exe -d $Distro
  if (-not (Wait-WslReady)) {
    Stop-WithMessage "$Distro n'a pas pu etre initialisee."
  }
}

if ($Mode -in @("Full", "Infrastructure")) {
  Set-DefaultWslDistribution
}

if ($Mode -eq "ResetStage") {
  if (-not $ConfirmDestructive) {
    Stop-WithMessage "La réinitialisation du Stage exige le paramètre -ConfirmDestructive."
  }

  Write-Step "Réinitialisation des conteneurs, volumes et données du Stage métier"
  & wsl.exe -d $Distro --cd $PackageRoot -- `
    bash ./installer/wsl/commands/reset-stage.sh --yes
  if ($LASTEXITCODE -ne 0) {
    Stop-WithMessage "La réinitialisation du Stage métier a échoué."
  }

  Add-Content -LiteralPath $LogFile -Value "Réinitialisation Stage terminée avec succès." -Encoding UTF8
  Write-Host ""
  Write-Host "Le Stage métier a été supprimé. Ubuntu WSL et l'infrastructure sont conservés." -ForegroundColor Green
  Write-Host "Tu peux maintenant relancer l'installation du Stage métier." -ForegroundColor Green
  Write-Host "Journal: $LogFile"
  exit 0
}

$WslLogFile = Convert-ToWslPath -WindowsPath $LogFile
$WslProvidedSources = Convert-ToWslPath -WindowsPath $ProvidedSourcesDir

Write-Step "Installation ORMT - mode $Mode - sources $SourceMode"
Write-Host "Journal: $LogFile"
if ($SelectGitBranches) {
  Write-Host "Branches Git: sélection interactive si plusieurs branches sont disponibles"
}
if ($SourceMode -ne "Git") {
  Write-Host "Dossiers fournis: $ProvidedSourcesDir"
}
Write-Host "Le mot de passe Linux peut etre demande; aucun caractere ne s'affichera."

$installerExitCode = 1
$restartCount = 0
$maxRestarts = 4

while ($true) {
  Invoke-WslInstaller `
    -WslLogFile $WslLogFile `
    -WslProvidedSources $WslProvidedSources
  $installerExitCode = $script:WslInstallerExitCode

  if ($installerExitCode -ne 42 -and $installerExitCode -ne 43) {
    break
  }

  $restartCount++
  if ($restartCount -gt $maxRestarts) {
    Stop-WithMessage "Trop de redemarrages WSL demandes ($restartCount)."
  }

  if ($installerExitCode -eq 42) {
    Restart-WslDistribution -Reason "activation de systemd"
  }
  else {
    Restart-WslDistribution -Reason "activation du groupe Docker"
  }
}

if ($installerExitCode -eq 44) {
  Add-Content -LiteralPath $LogFile -Value "Réinstallation du Stage annulée par l'utilisateur." -Encoding UTF8
  Write-Host ""
  Write-Host "Réinstallation annulée. Aucune donnée n'a été supprimée." -ForegroundColor Green
  Write-Host "Journal: $LogFile"
  exit 0
}

if ($installerExitCode -eq 45) {
  Add-Content -LiteralPath $LogFile -Value "Réinstallation des sources Git annulée par l'utilisateur." -Encoding UTF8
  Write-Host ""
  Write-Host "Mise à jour Git annulée. Aucune modification locale n'a été supprimée." -ForegroundColor Green
  Write-Host "Journal: $LogFile"
  exit 0
}

if ($installerExitCode -ne 0) {
  Stop-WithMessage "L'installation WSL a echoue avec le code $installerExitCode."
}

if ($Mode -in @("Full", "Infrastructure", "Stage", "Repair", "Diagnostic") -and
  (Test-FinalWslRestartRequested)) {
  Restart-WslDistribution -Reason "test final de démarrage à froid demandé"
  $validationScope = if ($Mode -eq "Infrastructure") { "infrastructure" } else { "stage" }
  Invoke-ColdStartValidation -Scope $validationScope -WslLogFile $WslLogFile
}

$finalLines = @(
  "",
  "============================================================",
  "SUCCES - mode $Mode termine et valide",
  ("Duree totale: {0:hh\:mm\:ss}" -f ((Get-Date) - $StartedAt)),
  "============================================================"
)
Add-Content -LiteralPath $LogFile -Value $finalLines -Encoding UTF8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "SUCCES - mode $Mode termine et valide" -ForegroundColor Green
Write-Host ("Duree totale: {0:hh\:mm\:ss}" -f ((Get-Date) - $StartedAt)) -ForegroundColor Green
Write-Host "Journal: $LogFile"
Write-Host "============================================================" -ForegroundColor Green
exit 0
