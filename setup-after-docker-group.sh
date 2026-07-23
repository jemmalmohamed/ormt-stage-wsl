#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

sudo service docker start >/dev/null 2>&1 || true

if ! docker ps >/dev/null 2>&1; then
  printf 'ERREUR: permission Docker toujours indisponible apres activation du groupe.\n' >&2
  exit 1
fi

log_phase() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$1"
}

log_phase "TEST 1/2 - Validation de l'infrastructure avec le groupe docker actif"
./test-infrastructure.sh

log_phase "DEMARRAGE STAGE"
./start-stage.sh

log_phase "TEST 2/2 - Validation fonctionnelle apres deploiement"
./test-stage.sh
