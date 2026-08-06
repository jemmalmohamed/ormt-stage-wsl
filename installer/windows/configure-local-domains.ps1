param(
  [switch]$Remove
)

$ErrorActionPreference = "Stop"

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdministrator) {
  $arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", ('"{0}"' -f $PSCommandPath)
  )
  if ($Remove) {
    $arguments += "-Remove"
  }

  $process = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $arguments
  exit $process.ExitCode
}

$hostsPath = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
$beginMarker = "# BEGIN ORMT STAGE DOMAINS"
$endMarker = "# END ORMT STAGE DOMAINS"
$domains = @(
  "ormt.local",
  "api.ormt.local",
  "content-api.ormt.local",
  "keycloak.ormt.local",
  "minio.ormt.local",
  "minio-console.ormt.local",
  "nextcloud.ormt.local",
  "traefik.ormt.local",
  "portainer.ormt.local",
  "jenkins.ormt.local",
  "homepage.ormt.local",
  "grafana.ormt.local",
  "prometheus.ormt.local"
)

$content = Get-Content -LiteralPath $hostsPath -Raw
$managedBlockPattern = "(?ms)^$([regex]::Escape($beginMarker))\r?\n.*?^$([regex]::Escape($endMarker))\r?\n?"
$content = [regex]::Replace($content, $managedBlockPattern, "").TrimEnd()

if (-not $Remove) {
  $entries = $domains | ForEach-Object { "127.0.0.1`t$_" }
  $managedBlock = @($beginMarker) + $entries + @($endMarker)
  $content = $content + [Environment]::NewLine + [Environment]::NewLine + ($managedBlock -join [Environment]::NewLine)
}

[System.IO.File]::WriteAllText(
  $hostsPath,
  $content + [Environment]::NewLine,
  [System.Text.UTF8Encoding]::new($false)
)

Clear-DnsClientCache

if ($Remove) {
  Write-Host "Domaines locaux ORMT supprimés du fichier hosts."
}
else {
  Write-Host "Domaines locaux ORMT configurés dans le fichier hosts."
}
