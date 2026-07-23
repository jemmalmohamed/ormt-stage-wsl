#!/usr/bin/env bash
set -Eeuo pipefail

LOG_NAME="${1:?Nom du fichier de log manquant}"
LOG_FILE="./logs/${LOG_NAME}"

mkdir -p ./logs
chmod +x ./setup.sh ./setup-after-docker-group.sh ./install-wsl-stage.sh \
  ./start-stage.sh ./status-stage.sh ./stop-stage.sh ./reset-stage.sh \
  ./sync-repositories.sh ./test-infrastructure.sh ./test-stage.sh \
  ./scripts/common.sh 2>/dev/null || true

# Force les outils Python/Ansible a emettre leurs lignes immediatement.
export PYTHONUNBUFFERED=1
export ANSIBLE_FORCE_COLOR=false

printf '\n[%s] Affichage detaille active (terminal + %s)\n' \
  "$(date '+%H:%M:%S')" "$LOG_FILE"

set -o pipefail
set +e
if [ -w /dev/tty ]; then
  # /dev/tty contourne le tampon d'affichage de wsl.exe dans CMD.
  stdbuf -oL -eL ./setup.sh 2>&1 | stdbuf -oL tee -a "$LOG_FILE" > /dev/tty
  setup_status="${PIPESTATUS[0]}"
else
  stdbuf -oL -eL ./setup.sh 2>&1 | stdbuf -oL tee -a "$LOG_FILE"
  setup_status="${PIPESTATUS[0]}"
fi
set -e
exit "$setup_status"
