#!/usr/bin/env bash

WSL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_ROOT="$(cd "$WSL_ROOT/../.." && pwd)"

# shellcheck disable=SC1091
source "$WSL_ROOT/lib/state.sh"
init_state

if [ -f "$STATE_ENV" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$STATE_ENV"
  set +a
fi

if [ -f "$STATE_SOURCE_ENV" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$STATE_SOURCE_ENV"
  set +a
fi

ORMT_INFRA_REPO_URL="${ORMT_INFRA_REPO_URL:-https://github.com/jemmalmohamed/ormt-infra-stage-local-vps.git}"
ORMT_API_REPO_URL="${ORMT_API_REPO_URL:-https://github.com/jemmalmohamed/ormt-api.git}"
ORMT_WEB_REPO_URL="${ORMT_WEB_REPO_URL:-https://github.com/jemmalmohamed/ormt-web-v1.git}"
ORMT_INFRA_BRANCH="${ORMT_INFRA_BRANCH:-}"
ORMT_API_BRANCH="${ORMT_API_BRANCH:-micro-service}"
ORMT_WEB_BRANCH="${ORMT_WEB_BRANCH:-micro-service}"
ORMT_SELECT_GIT_BRANCHES="${ORMT_SELECT_GIT_BRANCHES:-false}"
ORMT_SOURCE_MODE="${ORMT_SOURCE_MODE:-auto}"
ORMT_WSL_WORKSPACE="${ORMT_WSL_WORKSPACE:-${HOME}/ormt-app}"
ORMT_INSTALL_DEV_TOOLS="${ORMT_INSTALL_DEV_TOOLS:-true}"
ORMT_SKIP_TESTS="${ORMT_SKIP_TESTS:-false}"
ORMT_DOCKER_PULL_PARALLEL="${ORMT_DOCKER_PULL_PARALLEL:-4}"
ORMT_LINUX_USER="${ORMT_LINUX_USER:-${USER:-}}"

ORMT_WSL_WORKSPACE="$(realpath -m "$ORMT_WSL_WORKSPACE")"
ORMT_INFRA_DIR="${ORMT_INFRA_DIR:-${ORMT_WSL_WORKSPACE}/ormt-infra-stage-local-vps}"
ORMT_API_DIR="${ORMT_API_DIR:-${ORMT_WSL_WORKSPACE}/ormt-api}"
ORMT_WEB_DIR="${ORMT_WEB_DIR:-${ORMT_WSL_WORKSPACE}/ormt-web-v1}"
export COMPOSE_PROGRESS="${COMPOSE_PROGRESS:-plain}"
export BUILDKIT_PROGRESS="${BUILDKIT_PROGRESS:-plain}"
export DOCKER_BUILDKIT=1

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

set_progress() {
  test -n "${ORMT_PROGRESS_FILE:-}" || return 0
  printf '%s\n' "$*" > "$ORMT_PROGRESS_FILE"
}

clear_progress() {
  test -n "${ORMT_PROGRESS_FILE:-}" || return 0
  rm -f "$ORMT_PROGRESS_FILE"
}

show_third_party_apt_sources() {
  local apt_root="${1:-/etc/apt}"
  local source_file=""
  local urls=""
  local found=false

  while IFS= read -r source_file; do
    urls="$(grep -Eo 'https?://[^ /]+' "$source_file" 2>/dev/null || true)"
    test -n "$urls" || continue
    if grep -Evq '(^|\.)ubuntu\.com$' <<< "$urls"; then
      if test "$found" = false; then
        printf '\nDépôts APT tiers actifs à contrôler :\n' >&2
        found=true
      fi
      printf '  - %s\n' "$source_file" >&2
      printf '%s\n' "$urls" | sed 's/^/      /' >&2
    fi
  done < <(
    find "$apt_root" -maxdepth 2 -type f \
      \( -name '*.list' -o -name '*.sources' \) -print 2>/dev/null | sort
  )
}

update_apt_indexes() {
  local updated_at=""
  local now
  now="$(date +%s)"
  updated_at="$(state_value apt-indexes-updated-at 2>/dev/null || true)"

  if [[ "$updated_at" =~ ^[0-9]+$ ]] &&
    test "$((now - updated_at))" -ge 0 &&
    test "$((now - updated_at))" -lt 900; then
    log "Catalogues APT actualisés récemment : téléchargement ignoré"
    return 0
  fi

  if sudo apt-get \
    -o Acquire::Languages=none \
    -o Acquire::Retries=3 \
    update; then
    mark_state apt-indexes-updated-at "$now"
    return 0
  fi

  show_third_party_apt_sources
  die "APT n'a pas pu actualiser les catalogues. Consulte les lignes Err ci-dessus; aucun dépôt n'a été modifié par ORMT."
}

install_apt_packages() {
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

die() {
  printf '\nERREUR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Commande manquante: $1"
}

require_linux() {
  test "$(uname -s)" = "Linux" || die "Ce script doit être lancé dans Ubuntu WSL."
}

require_docker_ready() {
  need_cmd docker
  timeout 15 docker version >/dev/null 2>&1 ||
    die "Docker ne répond pas dans WSL."
}

require_project_dirs() {
  test -d "$ORMT_INFRA_DIR" || die "Dossier infrastructure absent: $ORMT_INFRA_DIR"
  test -d "$ORMT_API_DIR" || die "Dossier API absent: $ORMT_API_DIR"
  test -d "$ORMT_WEB_DIR" || die "Dossier frontend absent: $ORMT_WEB_DIR"
}

compose_up() {
  local workdir="$1"
  shift
  (cd "$workdir" && docker compose "$@" up -d)
}

compose_down() {
  local workdir="$1"
  shift
  (cd "$workdir" && docker compose "$@" down)
}

compose_down_volumes() {
  local workdir="$1"
  shift
  (cd "$workdir" && docker compose "$@" down -v)
}

wait_for_url() {
  local name="$1"
  local url="$2"
  local attempts="${3:-60}"
  local total_attempts="$attempts"
  local code="000"
  log "Attente: $name"
  while true; do
    code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' "$url" 2>/dev/null || true)"
    if [[ "$code" =~ ^(200|201|202|204|301|302)$ ]]; then
      break
    fi
    attempts=$((attempts - 1))
    test "$attempts" -gt 0 || die "$name indisponible: $url"
    set_progress "$name — contrôle HTTP $url — réponse ${code:-000} — tentative $((total_attempts - attempts))/$total_attempts"
    sleep 2
  done
  clear_progress
  log "OK: $name"
}

wait_for_host_route() {
  local name="$1"
  local host="$2"
  local path="$3"
  local attempts="${4:-60}"
  local total_attempts="$attempts"
  local code="000"
  local url="http://$host$path"
  log "Attente: $name"
  while true; do
    code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
      --header "Host: $host" "http://127.0.0.1$path" 2>/dev/null || true)"
    if [[ "$code" =~ ^(200|201|202|204|301|302)$ ]]; then
      break
    fi
    attempts=$((attempts - 1))
    test "$attempts" -gt 0 || die "$name indisponible: $url (dernière réponse HTTP: ${code:-000})"
    set_progress "$name — contrôle HTTP $url — réponse ${code:-000} — tentative $((total_attempts - attempts))/$total_attempts"
    sleep 2
  done
  clear_progress
  log "OK: $name"
}

wait_for_container_health() {
  local container="$1"
  local attempts="${2:-60}"
  local total_attempts="$attempts"
  local health="unknown"
  log "Attente healthcheck: $container"
  while true; do
    health="$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || true)"
    test "$health" = "healthy" && break
    attempts=$((attempts - 1))
    if test "$attempts" -le 0; then
      docker logs --tail 80 "$container" 2>/dev/null || true
      die "$container n'est pas healthy"
    fi
    set_progress "$container — healthcheck Docker: ${health:-absent} — tentative $((total_attempts - attempts))/$total_attempts"
    sleep 2
  done
  clear_progress
}

verify_proxy() {
  docker network inspect proxy >/dev/null 2>&1 ||
    die "Le réseau Docker 'proxy' est absent."
  local proxy_container
  proxy_container="$(docker ps --format '{{.Names}}|{{.Image}}' |
    awk -F'|' 'tolower($2) ~ /traefik/ {print $1; exit}')"
  test -n "$proxy_container" || die "Aucun conteneur Traefik actif."
  docker network connect proxy "$proxy_container" >/dev/null 2>&1 || true
}

api_service_compose_args() {
  printf '%s\n' \
    --env-file ./docker/app/env/.env.stage \
    -f ./docker/app/docker-compose.ormt-core-api.base.yml \
    -f ./docker/app/docker-compose.ormt-core-api.stage.yml \
    -f ./docker/app/docker-compose.ormt-content-api.base.yml \
    -f ./docker/app/docker-compose.ormt-content-api.stage.yml \
    --project-name ormt-services
}

source_fingerprint() {
  local dir="$1"
  if test "$(state_value source-mode 2>/dev/null || true)" != "provided" &&
    test -d "$dir/.git"; then
    {
      git -C "$dir" rev-parse HEAD
      git -C "$dir" status --porcelain
    } | sha256sum | awk '{print $1}'
    return
  fi

  find "$dir" -type f \
    ! -path '*/.git/*' \
    ! -path '*/target/*' \
    ! -path '*/node_modules/*' \
    ! -path '*/dist/*' \
    -printf '%P|%s|%T@\n' |
    sort | sha256sum | awk '{print $1}'
}

api_image_exists() {
  docker image inspect ormt/ormt-core-api:latest >/dev/null 2>&1 &&
    docker image inspect ormt/ormt-content-api:latest >/dev/null 2>&1
}

web_image_exists() {
  docker image inspect ormt/ormt-web-stage:latest >/dev/null 2>&1
}
