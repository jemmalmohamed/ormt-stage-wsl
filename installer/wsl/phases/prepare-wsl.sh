#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_linux

log "Vérification des droits administrateur"
if ! sudo -n true 2>/dev/null; then
  printf '\n============================================================\n'
  printf 'ACTION REQUISE\n'
  printf 'Saisis le mot de passe Linux de %s.\n' "$USER"
  printf 'Aucun caractère ne sera affiché pendant la saisie.\n'
  printf '============================================================\n\n'
  sudo -v -p "[sudo] Mot de passe Linux pour %u : " ||
    die "L'utilisateur $USER doit disposer des droits sudo."
fi

if ! test -f /etc/wsl.conf || ! grep -q '^systemd=true' /etc/wsl.conf; then
  log "Activation de systemd dans WSL"
  printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf >/dev/null
  mark_state systemd-configured
  printf '\nWSL va redémarrer automatiquement pour activer systemd.\n'
  exit 42
fi

log "Préparation WSL validée"

