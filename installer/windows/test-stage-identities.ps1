#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$IdentityPath = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($IdentityPath)) {
    $IdentityPath = Join-Path $PSScriptRoot '../../config/identity.stage.local.env'
}

# Vérification du jeu fictif généré ; aucune valeur secrète dans les sorties.
$values = @{}
foreach ($line in [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $IdentityPath))) {
    if (-not $line -or $line.StartsWith('#')) { continue }
    $separator = $line.IndexOf('=')
    if ($separator -lt 1) { throw 'Clé invalide ou dupliquée.' }
    $key = $line.Substring(0, $separator)
    if ($values.ContainsKey($key)) { throw 'Clé invalide ou dupliquée.' }
    $values[$key] = $line.Substring($separator + 1)
}
function Assert-Stage([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
$secretKeys = @('KC_BOOTSTRAP_ADMIN_PASSWORD', 'ORMT_KEYCLOAK_SERVICE_CLIENT_SECRET')
$expectedUsers = @{ ORMT_BOOTSTRAP_MASTER = 'o.master'; ORMT_BOOTSTRAP_ADMIN = 'o.admin'; ORMT_KEYCLOAK_CONSOLE_ADMIN = 'admin' }
$usernames = @()
$emails = @()
foreach ($prefix in @('ORMT_BOOTSTRAP_MASTER', 'ORMT_BOOTSTRAP_ADMIN', 'ORMT_KEYCLOAK_CONSOLE_ADMIN')) {
    $usernames += $values[$prefix + '_USERNAME']
    $emails += $values[$prefix + '_EMAIL']
    Assert-Stage ($values[$prefix + '_USERNAME'] -ceq $expectedUsers[$prefix]) 'Identité de test Stage attendue.'
    Assert-Stage ($values[$prefix + '_EMAIL'] -cmatch '^[a-z0-9.]+@ormt\.test$') 'Domaine de test attendu.'
    $temporary = if ($prefix -eq 'ORMT_KEYCLOAK_CONSOLE_ADMIN') { 'false' } else { 'true' }
    Assert-Stage ($values[$prefix + '_TEMPORARY_PASSWORD'] -ceq $temporary) 'Politique de mot de passe Stage incorrecte.'
    Assert-Stage (-not [string]::IsNullOrWhiteSpace($values[$prefix + '_FIRST_NAME'])) 'Prénom absent.'
    Assert-Stage (-not [string]::IsNullOrWhiteSpace($values[$prefix + '_LAST_NAME'])) 'Nom absent.'
    if ($prefix -ne 'ORMT_KEYCLOAK_CONSOLE_ADMIN') {
        Assert-Stage ($values[$prefix + '_INITIAL_PASSWORD'] -ceq 'ormt') 'Mot de passe ORMT Stage incorrect.'
    }
}
Assert-Stage ($values['ORMT_KEYCLOAK_CONSOLE_ADMIN_INITIAL_PASSWORD'] -ceq 'admin') 'Mot de passe de console Stage incorrect.'
Assert-Stage (@($usernames | Select-Object -Unique).Count -eq 3) 'Les utilisateurs doivent être distincts.'
Assert-Stage (@($emails | Select-Object -Unique).Count -eq 3) 'Les e-mails doivent être distincts.'
foreach ($key in $secretKeys) {
    Assert-Stage ($values[$key] -cmatch '^[0-9a-f]{64}$') ('Format du secret invalide : ' + $key)
}
Assert-Stage (@($secretKeys | ForEach-Object { $values[$_] } | Select-Object -Unique).Count -eq $secretKeys.Count) 'Les secrets doivent être distincts.'
Assert-Stage ($values['SMTP_HOST'] -ceq 'ormt-mailpit' -and $values['SMTP_PORT'] -ceq '1025') 'Relais Mailpit attendu.'
Assert-Stage ($values['SMTP_AUTH'] -ceq 'false' -and $values['SMTP_STARTTLS_ENABLE'] -ceq 'false') 'Transport SMTP de capture attendu.'
Assert-Stage ($values['SMTP_USERNAME'] -ceq '' -and $values['SMTP_PASSWORD'] -ceq '') 'Aucun identifiant SMTP réel attendu.'
Assert-Stage ($values['MAILING_FROM_EMAIL'] -ceq 'noreply@ormt.test' -and $values['KEYCLOAK_SMTP_FROM'] -ceq 'noreply@ormt.test') 'Expéditeurs de test attendus.'
$before = (Get-FileHash -LiteralPath $IdentityPath -Algorithm SHA256).Hash
$refused = $false
try { & (Join-Path $PSScriptRoot 'generate-stage-identities.ps1') -OutputPath $IdentityPath }
catch { $refused = $_.Exception.Message -like 'Le fichier existe déjà*' }
Assert-Stage $refused 'Le générateur doit refuser un fichier existant.'
Assert-Stage ((Get-FileHash -LiteralPath $IdentityPath -Algorithm SHA256).Hash -ceq $before) 'Le fichier existant a changé.'
Assert-Stage ((Get-Acl -LiteralPath $IdentityPath).AreAccessRulesProtected) 'ACL privée attendue.'
$values.Clear()
Write-Host "OK : 3 identités fictives, secrets distincts, SMTP de capture, ACL protégée et refus d'écrasement."
