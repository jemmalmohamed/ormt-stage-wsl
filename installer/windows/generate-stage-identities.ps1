#requires -Version 5.1
<#
.SYNOPSIS
Génère les identités fictives Stage et leurs secrets dans un fichier local privé.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '../../config/identity.stage.local.env')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function New-StageSecret {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([System.BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}

$destination = [System.IO.Path]::GetFullPath($OutputPath)
if (-not $destination.EndsWith('.local.env', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Le fichier de sortie doit se terminer par .local.env.'
}
if (Test-Path -LiteralPath $destination) {
    throw 'Le fichier existe déjà : génération arrêtée pour préserver les identités et secrets actuels.'
}
if (-not (Test-Path -LiteralPath ([System.IO.Path]::GetDirectoryName($destination)) -PathType Container)) {
    throw 'Le dossier de sortie doit exister.'
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# Identités fictives STAGE uniquement. Fichier privé, ne pas versionner.')
$lines.Add('# Généré localement ; aucun compte créé et aucun service démarré.')
$lines.Add('')
$lines.Add('# 1. Bootstrap jetable et client technique permanent')
$lines.Add('KC_BOOTSTRAP_ADMIN_USERNAME=ormt-stage-bootstrap')
$lines.Add('KC_BOOTSTRAP_ADMIN_PASSWORD=' + (New-StageSecret))
$lines.Add('ORMT_KEYCLOAK_SERVICE_CLIENT_SECRET=' + (New-StageSecret))

$accounts = @(
    @{ Prefix = 'ORMT_BOOTSTRAP_MASTER'; Username = 'sara.stage'; FirstName = 'Sara'; LastName = 'StageMaster' },
    @{ Prefix = 'ORMT_BOOTSTRAP_ADMIN'; Username = 'amine.stage'; FirstName = 'Amine'; LastName = 'StageAdmin' },
    @{ Prefix = 'ORMT_KEYCLOAK_CONSOLE_ADMIN'; Username = 'lina.stage'; FirstName = 'Lina'; LastName = 'StageIdentites' }
)
foreach ($account in $accounts) {
    $lines.Add('')
    $lines.Add('# Identité humaine de test : ' + $account.Prefix)
    $lines.Add($account.Prefix + '_USERNAME=' + $account.Username)
    $lines.Add($account.Prefix + '_EMAIL=' + $account.Username + '@ormt.test')
    $lines.Add($account.Prefix + '_FIRST_NAME=' + $account.FirstName)
    $lines.Add($account.Prefix + '_LAST_NAME=' + $account.LastName)
    $lines.Add($account.Prefix + '_INITIAL_PASSWORD=' + (New-StageSecret))
    $lines.Add($account.Prefix + '_TEMPORARY_PASSWORD=true')
}

$lines.Add('')
$lines.Add('# 2. SMTP ORMT et Keycloak : capture locale Mailpit, indépendant de la plateforme')
foreach ($entry in @(
    'SMTP_HOST=ormt-mailpit', 'SMTP_PORT=1025', 'SMTP_AUTH=false',
    'SMTP_STARTTLS_ENABLE=false', 'SMTP_USERNAME=', 'SMTP_PASSWORD=',
    'MAILING_FROM_EMAIL=noreply@ormt.test', 'KEYCLOAK_SMTP_FROM=noreply@ormt.test'
)) { $lines.Add($entry) }

$lines.Add('')
# Créer exclusivement un nouveau fichier vide, limiter son ACL avant d'y écrire les secrets.
$stream = [System.IO.File]::Open($destination, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
$stream.Dispose()
try {
    $acl = Get-Acl -LiteralPath $destination
    $acl.SetAccessRuleProtection($true, $false)
    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -LiteralPath $destination -AclObject $acl
    [System.IO.File]::WriteAllText($destination, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
} catch {
    # Le fichier a été créé exclusivement par cette exécution et reste dans le chemin vérifié.
    Remove-Item -LiteralPath $destination -ErrorAction SilentlyContinue
    throw
} finally {
    $lines.Clear()
}
Write-Host ('Fichier privé créé : {0}' -f $destination)
Write-Host '3 identités de test ; SMTP Mailpit ; mots de passe temporaires.'
