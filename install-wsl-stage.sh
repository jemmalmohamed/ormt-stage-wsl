#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/common.sh"

require_linux
need_cmd sudo

if [ ! -f "$ROOT_DIR/.env" ]; then
  log "Création du fichier .env depuis .env.example"
  cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
fi

log "Installation des prérequis système"
sudo apt update
sudo apt install -y git ansible python3-pip curl ca-certificates

need_cmd git

clone_if_missing "$ORMT_INFRA_DIR" "$ORMT_INFRA_REPO_URL" "ormt-infra-stage-local-vps" "$ORMT_INFRA_BRANCH"
clone_if_missing "$ORMT_API_DIR" "$ORMT_API_REPO_URL" "ormt-api" "$ORMT_API_BRANCH"
clone_if_missing "$ORMT_WEB_DIR" "$ORMT_WEB_REPO_URL" "ormt-web-v1" "$ORMT_WEB_BRANCH"

[ -n "$ORMT_LINUX_USER" ] || die "Utilisateur Linux introuvable. Définis ORMT_LINUX_USER dans .env."

log "Installation des collections Ansible"
(cd "$ORMT_INFRA_DIR/ansible" && ansible-galaxy collection install -r requirements.yml)

log "Installation de l'infra partagée avec Ansible"
ansible_args=(
  -i inventory/hosts
  all.playbook.yml
  -e "username=$ORMT_LINUX_USER system_upgrade_packages=false docker_enable_tcp=false"
)

if [ "$ORMT_INSTALL_DEV_TOOLS" != "true" ]; then
  log "Mode léger: Homepage, Portainer, monitoring et Jenkins sont ignorés"
  ansible_args+=(--skip-tags homepage,portainer,monitoring,jenkins)
fi

(cd "$ORMT_INFRA_DIR/ansible" && ansible-playbook -v "${ansible_args[@]}")

log "Validation Docker et proxy"
sudo service docker start >/dev/null 2>&1 || true
if ! timeout 15 docker version >/dev/null 2>&1; then
  if timeout 15 sudo docker version >/dev/null 2>&1; then
    cat <<'MSG'

Docker fonctionne, mais l'utilisateur courant n'a pas encore la permission directe.
Le script principal setup.sh active le groupe docker automatiquement pour la suite.
MSG
  else
    require_docker_ready
  fi
else
  require_docker_ready
fi
docker compose version
if docker network inspect proxy >/dev/null 2>&1; then
  docker ps
else
  sudo docker network inspect proxy >/dev/null
  sudo docker ps
fi

if [ "$ORMT_INSTALL_DEV_TOOLS" = "true" ]; then
  install_mode="complete"
else
  install_mode="light"
fi
printf '%s|%s|%s\n' "$install_mode" "$ORMT_API_BRANCH" "$ORMT_WEB_BRANCH" > "$ROOT_DIR/.infra-installed"

cat <<'MSG'

Installation terminée.
Si docker répond "permission denied", ouvre un nouveau terminal WSL ou lance:
  newgrp docker

Ensuite:
  ./start-stage.sh
MSG
