#!/usr/bin/env bash

ensure_docker_service() {
  sudo service docker start >/dev/null 2>&1 || true
}

ensure_docker_group() {
  local linux_user="${1:?Utilisateur Linux manquant}"
  sudo groupadd --force docker

  if getent group docker | cut -d: -f4 | tr ',' '\n' | grep -Fxq "$linux_user"; then
    return 0
  fi

  log "Ajout de $linux_user au groupe Docker"
  sudo usermod --append --groups docker "$linux_user"
  mark_state docker-group-refresh-required
  return 43
}

docker_session_ready() {
  id -nG | tr ' ' '\n' | grep -Fxq docker &&
    timeout 15 docker ps >/dev/null 2>&1
}
