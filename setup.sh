#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
TARGET_ROOT="${HOME}/ormt-app"
TARGET_DIR="${TARGET_ROOT}/ormt-stage-wsl"

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  printf '\nERREUR: %s\n' "$*" >&2
  exit 1
}

show_failure() {
  local exit_code=$?
  local line="$1"
  local command="$2"

  printf '\n============================================================\n' >&2
  printf 'ÉCHEC DE L’INSTALLATION\n' >&2
  if [ -n "${CURRENT_STEP:-}" ]; then
    printf 'Etape          : %s\n' "$CURRENT_STEP" >&2
  fi
  printf 'Commande       : %s\n' "$command" >&2
  printf 'Ligne          : %s\n' "$line" >&2
  printf 'Code erreur    : %s\n' "$exit_code" >&2
  printf 'Relance setup.bat : les étapes déjà terminées seront réutilisées.\n' >&2
  printf '============================================================\n' >&2
}

trap 'show_failure "$LINENO" "$BASH_COMMAND"' ERR

run_with_heartbeat() {
  local label="$1"
  shift

  CURRENT_STEP="$label"
  log "$label"
  "$@" &
  local pid=$!
  local seconds=0

  while kill -0 "$pid" 2>/dev/null; do
    sleep 30
    seconds=$((seconds + 30))
    if kill -0 "$pid" 2>/dev/null; then
      log "$label - aucun nouveau log depuis la commande (${seconds}s)"
      printf 'Processus actifs lies a l installation:\n'
      ps -eo etime=,stat=,comm=,args= \
        | awk '$3 ~ /^(ansible.*|apt|apt-get|dpkg|mvn|java|docker|npm|node)$/ {
            printf "  duree=%-10s etat=%-4s processus=%-18s %s\n", $1, $2, $3, substr($0, index($0,$4))
          }' \
        | tail -n 12 || true
    fi
  done

  if wait "$pid"; then
    log "$label termine avec succes"
    CURRENT_STEP=""
  else
    local status=$?
    printf '\nERREUR: %s a echoue (code %s).\n' "$label" "$status" >&2
    return "$status"
  fi
}

infra_ready() {
  local expected_mode="complete"
  local api_branch="micro-service"
  local web_branch="micro-service"
  if grep -q '^ORMT_INSTALL_DEV_TOOLS=false' .env 2>/dev/null; then
    expected_mode="light"
  fi
  api_branch="$(sed -n 's/^ORMT_API_BRANCH=//p' .env | tail -n 1)"
  web_branch="$(sed -n 's/^ORMT_WEB_BRANCH=//p' .env | tail -n 1)"
  api_branch="${api_branch:-micro-service}"
  web_branch="${web_branch:-micro-service}"

  [ -f .infra-installed ] || return 1
  grep -Fqx "${expected_mode}|${api_branch}|${web_branch}" .infra-installed || return 1
  command -v docker >/dev/null 2>&1 || return 1
  timeout 10 docker network inspect proxy >/dev/null 2>&1 || return 1
  timeout 10 docker ps --format '{{.Names}}|{{.Image}}' | awk -F'|' 'tolower($2) ~ /traefik/ {found=1} END {exit found ? 0 : 1}'
}

if [ "$(uname -s)" != "Linux" ]; then
  die "Lance ce script dans Ubuntu WSL."
fi

if [[ "$SCRIPT_DIR" == /mnt/* ]]; then
  log "Le dossier est dans Windows. Copie automatique vers $TARGET_DIR"
  mkdir -p "$TARGET_ROOT"
  rm -rf "$TARGET_DIR"
  cp -R "$SCRIPT_DIR" "$TARGET_DIR"
  chmod +x "$TARGET_DIR"/*.sh "$TARGET_DIR"/scripts/*.sh 2>/dev/null || true
  cd "$TARGET_DIR"
  exec ./setup.sh "$@"
fi

cd "$SCRIPT_DIR"

log "Préparation des permissions des scripts"
chmod +x ./*.sh scripts/*.sh 2>/dev/null || true

if [ ! -f .env ]; then
  log "Création automatique du fichier .env"
  cp .env.example .env
fi

if ! grep -q '^ORMT_LINUX_USER=' .env || grep -q '^ORMT_LINUX_USER=$' .env; then
  log "Configuration automatique de l'utilisateur Linux: ${USER}"
  if grep -q '^ORMT_LINUX_USER=' .env; then
    sed -i "s/^ORMT_LINUX_USER=.*/ORMT_LINUX_USER=${USER}/" .env
  else
    printf '\nORMT_LINUX_USER=%s\n' "$USER" >> .env
  fi
fi

log "Vérification des droits sudo"
if sudo -n true 2>/dev/null; then
  log "Droits administrateur déjà disponibles"
else
  printf '\n============================================================\n'
  printf 'ACTION REQUISE\n'
  printf 'Saisis maintenant le mot de passe Linux de %s.\n' "$USER"
  printf 'Aucun caractère ne s’affichera pendant la saisie : c’est normal.\n'
  printf 'Appuie ensuite sur Entrée.\n'
  printf '============================================================\n\n'
  sudo -v -p "[sudo] Mot de passe Linux pour %u : " || die "L'utilisateur ${USER} doit avoir les droits sudo."
fi

if [ ! -f /etc/wsl.conf ] || ! grep -q '^systemd=true' /etc/wsl.conf; then
  log "Activation de systemd dans WSL"
  sudo mkdir -p /etc
  printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf >/dev/null
  cat <<'MSG'

systemd vient d'être activé.
Ferme Ubuntu, puis lance dans PowerShell:
  wsl --shutdown

Ensuite rouvre Ubuntu et relance:
  cd ~/ormt-app/ormt-stage-wsl
  ./setup.sh
MSG
  exit 0
fi

if infra_ready; then
  log "Infra déjà prête: Ansible est ignoré"
else
  run_with_heartbeat "Installation et configuration ORMT Stage" ./install-wsl-stage.sh
fi

if command -v docker >/dev/null 2>&1; then
  log "Démarrage de Docker si nécessaire"
  sudo service docker start >/dev/null 2>&1 || true

  if ! getent group docker | cut -d: -f4 | tr ',' '\n' | grep -Fxq "$USER"; then
    log "Ajout automatique de $USER au groupe docker"
    sudo groupadd --force docker
    sudo usermod --append --groups docker "$USER"
  fi

  if ! docker ps >/dev/null 2>&1; then
    log "Activation immédiate du groupe docker pour cette session"
    exec sg docker -c "cd '$SCRIPT_DIR' && ./setup-after-docker-group.sh"
  fi
fi

log "TEST 1/2 - Validation de l'infrastructure avant Stage"
./test-infrastructure.sh

run_with_heartbeat "DEMARRAGE STAGE - construction et lancement des services" ./start-stage.sh

log "TEST 2/2 - Validation fonctionnelle apres deploiement"
./test-stage.sh
