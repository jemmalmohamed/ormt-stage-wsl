#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/docker.sh"

require_linux
need_cmd sudo
test -d "$ORMT_INFRA_DIR/ansible" ||
  die "Sources infrastructure invalides: $ORMT_INFRA_DIR"

log "Installation des prérequis système"
set_progress "Paquets Ubuntu — actualisation des catalogues (apt-get update)"
update_apt_indexes
set_progress "Paquets Ubuntu — installation de Git, Ansible, Python, curl et des certificats"
install_apt_packages git ansible python3-pip curl ca-certificates

log "Installation des collections Ansible"
set_progress "Ansible Galaxy — installation des collections requises"
(cd "$ORMT_INFRA_DIR/ansible" &&
  ansible-galaxy collection install -r requirements.yml)

log "Installation du système et de Docker avec Ansible"
set_progress "Ansible système — préparation du moteur Docker et de l'utilisateur Linux"
base_ansible_args=(
  -i inventory/hosts
  all.playbook.yml
  -e "username=$ORMT_LINUX_USER system_upgrade_packages=false docker_enable_tcp=false"
  --skip-tags traefik,homepage,portainer,monitoring,jenkins
)

clear_progress
(cd "$ORMT_INFRA_DIR/ansible" &&
  ansible-playbook -v "${base_ansible_args[@]}")

set_progress "Docker — vérification du service puis téléchargement des images d'infrastructure"
ensure_docker_service
prefetch_docker_images \
  "$ORMT_INFRA_DIR/ansible/roles/docker-containers/containers" \
  "${ORMT_DOCKER_PULL_PARALLEL:-4}"

log "Configuration et démarrage des conteneurs avec Ansible"
set_progress "Ansible conteneurs — préparation de Traefik et des outils d'infrastructure"
container_ansible_args=(
  -i inventory/hosts
  docker-containers.playbook.yml
  -e "username=$ORMT_LINUX_USER"
)

if test "$ORMT_INSTALL_DEV_TOOLS" != "true"; then
  log "Profil léger demandé: outils développeur ignorés"
  container_ansible_args+=(--skip-tags homepage,portainer,monitoring,jenkins)
fi

clear_progress
(cd "$ORMT_INFRA_DIR/ansible" &&
  ansible-playbook -v "${container_ansible_args[@]}")

set_progress "Infrastructure — vérification finale de Docker, du groupe utilisateur et du réseau proxy"
ensure_docker_service
mark_state infrastructure-installed "$ORMT_INSTALL_DEV_TOOLS"

group_status=0
ensure_docker_group "$ORMT_LINUX_USER" || group_status=$?
if test "$group_status" -eq 43 || ! docker_session_ready; then
  mark_state docker-group-refresh-required
  printf '\nLe groupe Docker est configuré. WSL va redémarrer automatiquement.\n'
  exit 43
fi

docker compose version
docker network inspect proxy >/dev/null
clear_progress
log "Infrastructure installée"
