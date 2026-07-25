param(
  [ValidateSet("Full", "Infrastructure", "Stage", "Diagnostic", "Repair")]
  [string]$Mode = "Full",

  [ValidateSet("Auto", "Provided", "Git")]
  [string]$SourceMode = "Auto",

  [string]$ProvidedSourcesDir = "",
  [string]$Distro = "Ubuntu-24.04"
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

function Convert-ToWslPath {
  param([string]$WindowsPath)
  $converted = & wsl.exe -d $Distro -- wslpath -a -u $WindowsPath 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($converted | Out-String))) {
    Stop-WithMessage "Impossible de convertir le chemin Windows pour WSL: $WindowsPath"
  }
  return (($converted | Select-Object -First 1).Trim())
}

function Invoke-WslInstaller {
  param(
    [string]$WslLogFile,
    [string]$WslProvidedSources
  )

  & wsl.exe -d $Distro --cd $PackageRoot -- `
    bash ./installer/wsl/setup.sh `
      --mode $Mode `
      --source-mode $SourceMode `
      --log-file $WslLogFile `
      --provided-sources-dir $WslProvidedSources

  # Ne pas retourner la sortie standard dans une affectation PowerShell : elle
  # doit rester directement reliee au terminal pour sudo. Seul le code est
  # enregistre separement afin d'eviter la fausse erreur historique.
  $script:WslInstallerExitCode = $LASTEXITCODE
}

function Restart-WslDistribution {
  param([string]$Reason)
  Write-Step "Redemarrage automatique de WSL - $Reason"
  Add-Content -LiteralPath $LogFile -Value "Execution: wsl.exe --terminate $Distro" -Encoding UTF8
  & wsl.exe --terminate $Distro
  if ($LASTEXITCODE -ne 0) {
    Stop-WithMessage "Impossible d'arreter la distribution $Distro."
  }
  Start-Sleep -Seconds 3
  if (-not (Wait-WslReady)) {
    Stop-WithMessage "$Distro ne redemarre pas apres son arret."
  }
}

$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslCommand) {
  Stop-WithMessage "WSL n'est pas disponible sur ce PC."
}

$hasDistro = Test-WslReady

if (-not $hasDistro) {
  if ($Mode -eq "Diagnostic") {
    Stop-WithMessage "$Distro n'est pas installee; aucun diagnostic n'est possible."
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

$WslLogFile = Convert-ToWslPath -WindowsPath $LogFile
$WslProvidedSources = Convert-ToWslPath -WindowsPath $ProvidedSourcesDir

Write-Step "Installation ORMT - mode $Mode - sources $SourceMode"
Write-Host "Journal: $LogFile"
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

if ($installerExitCode -ne 0) {
  Stop-WithMessage "L'installation WSL a echoue avec le code $installerExitCode."
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
