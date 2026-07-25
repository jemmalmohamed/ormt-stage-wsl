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

prefetch_docker_images() {
  local sources_root="${1:?Dossier des stacks Docker manquant}"
  local max_parallel="${2:-4}"
  local definition_file=""
  local image=""
  local -a discovered_images=()
  local -a missing_images=()

  while IFS= read -r -d '' definition_file; do
    while IFS= read -r image; do
      image="${image#*:}"
      image="${image#${image%%[![:space:]]*}}"
      image="${image%${image##*[![:space:]]}}"
      image="${image%\"}"
      image="${image#\"}"
      image="${image%\'}"
      image="${image#\'}"
      if [[ "$image" =~ ^\$\{[^:}]+:-([^}]+)\}$ ]]; then
        image="${BASH_REMATCH[1]}"
      elif [[ "$image" == *'$'* ]]; then
        continue
      fi
      test -n "$image" && discovered_images+=("$image")
    done < <(grep -E '^[[:space:]]*image[[:space:]]*:' "$definition_file" || true)

    while IFS= read -r image; do
      image="$(awk '{print $2}' <<< "$image")"
      test -n "$image" && discovered_images+=("$image")
    done < <(grep -Ei '^[[:space:]]*FROM[[:space:]]+' "$definition_file" || true)
  done < <(find "$sources_root" -type f \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'Dockerfile' \) -print0)

  mapfile -t discovered_images < <(printf '%s\n' "${discovered_images[@]}" | sed '/^$/d' | sort -u)
  for image in "${discovered_images[@]}"; do
    if ! sudo docker image inspect "$image" >/dev/null 2>&1; then
      missing_images+=("$image")
    fi
  done

  if test "${#missing_images[@]}" -eq 0; then
    log "Images Docker déjà présentes: aucun téléchargement nécessaire"
    return 0
  fi

  printf '\nTéléchargement parallèle de %d image(s), maximum %d à la fois :\n' \
    "${#missing_images[@]}" "$max_parallel"
  printf '  - %s\n' "${missing_images[@]}"
  printf '%s\0' "${missing_images[@]}" \
    | xargs -0 -r -n 1 -P "$max_parallel" sudo docker pull
  log "Préchargement des images Docker terminé"
}
