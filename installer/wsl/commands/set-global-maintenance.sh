#!/usr/bin/env bash
set -Eeuo pipefail

ACTIVE=""
LOG_FILE=""

while test "$#" -gt 0; do
  case "$1" in
    --active)
      ACTIVE="${2:?Valeur --active manquante}"
      shift 2
      ;;
    --log-file)
      LOG_FILE="${2:?Valeur --log-file manquante}"
      shift 2
      ;;
    *)
      printf 'ERREUR: argument inconnu: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

case "${ACTIVE,,}" in
  true|false) ACTIVE="${ACTIVE,,}" ;;
  *)
    printf 'ERREUR: passer --active true ou --active false.\n' >&2
    exit 2
    ;;
esac

if test -n "$LOG_FILE"; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

ANSIBLE_DIR="$ORMT_INFRA_DIR/ansible"
PLAYBOOK="$ANSIBLE_DIR/maintenance-globale.playbook.yml"

command -v ansible-playbook >/dev/null 2>&1 ||
  die "Ansible n'est pas installé dans WSL. Installe d'abord l'infrastructure."
command -v docker >/dev/null 2>&1 ||
  die "Docker n'est pas installé dans WSL. Installe d'abord l'infrastructure."
docker info >/dev/null 2>&1 ||
  die "Docker n'est pas accessible. Vérifie que WSL et Docker sont démarrés."
test -f "$PLAYBOOK" ||
  die "Playbook de maintenance introuvable: $PLAYBOOK. Installe ou mets à jour l'infrastructure."

log "Application de maintenance_active=$ACTIVE"
(
  cd "$ANSIBLE_DIR"
  ansible-playbook -i inventory/hosts \
    maintenance-globale.playbook.yml \
    -e "maintenance_active=$ACTIVE"
)

if test "$ACTIVE" = "true"; then
  log "Maintenance locale activée et vérifiée sur http://ormt.localhost"
else
  log "Maintenance locale désactivée et vérifiée sur http://ormt.localhost"
fi
