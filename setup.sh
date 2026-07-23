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

run_with_heartbeat() {
  local label="$1"
  shift

  log "$label"
  "$@" &
  local pid=$!
  local seconds=0

  while kill -0 "$pid" 2>/dev/null; do
    sleep 30
    seconds=$((seconds + 30))
    if kill -0 "$pid" 2>/dev/null; then
      log "$label toujours en cours (${seconds}s)"
    fi
  done

  wait "$pid"
}

infra_ready() {
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
echo "Si le mot de passe est demandé, saisis le mot de passe Linux de ${USER}, puis appuie sur Entrée."
echo "Le mot de passe ne s'affiche pas pendant la saisie."
sudo -v -p "[sudo] Mot de passe Linux pour %u: " || die "L'utilisateur ${USER} doit avoir les droits sudo."

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

  if ! docker ps >/dev/null 2>&1; then
    log "Activation immédiate du groupe docker pour cette session"
    exec sg docker -c "cd '$SCRIPT_DIR' && ./setup-after-docker-group.sh"
  fi
fi

run_with_heartbeat "Démarrage ORMT Stage" ./start-stage.sh

log "Diagnostic final"
./status-stage.sh
