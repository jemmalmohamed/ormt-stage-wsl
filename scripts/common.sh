#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

ORMT_INFRA_REPO_URL="${ORMT_INFRA_REPO_URL:-https://github.com/jemmalmohamed/ormt-infra-stage-local-vps.git}"
ORMT_API_REPO_URL="${ORMT_API_REPO_URL:-https://github.com/jemmalmohamed/ormt-api.git}"
ORMT_WEB_REPO_URL="${ORMT_WEB_REPO_URL:-https://github.com/jemmalmohamed/ormt-web-v1.git}"
ORMT_INFRA_BRANCH="${ORMT_INFRA_BRANCH:-}"
ORMT_API_BRANCH="${ORMT_API_BRANCH:-micro-service}"
ORMT_WEB_BRANCH="${ORMT_WEB_BRANCH:-micro-service}"

ORMT_INFRA_DIR="${ORMT_INFRA_DIR:-../ormt-infra-stage-local-vps}"
ORMT_API_DIR="${ORMT_API_DIR:-../ormt-api}"
ORMT_WEB_DIR="${ORMT_WEB_DIR:-../ormt-web-v1}"

ORMT_INFRA_DIR="$(cd "$ROOT_DIR" && mkdir -p "$(dirname "$ORMT_INFRA_DIR")" && realpath -m "$ORMT_INFRA_DIR")"
ORMT_API_DIR="$(cd "$ROOT_DIR" && mkdir -p "$(dirname "$ORMT_API_DIR")" && realpath -m "$ORMT_API_DIR")"
ORMT_WEB_DIR="$(cd "$ROOT_DIR" && mkdir -p "$(dirname "$ORMT_WEB_DIR")" && realpath -m "$ORMT_WEB_DIR")"

ORMT_LINUX_USER="${ORMT_LINUX_USER:-${USER:-}}"
ORMT_SKIP_TESTS="${ORMT_SKIP_TESTS:-false}"
ORMT_INSTALL_DEV_TOOLS="${ORMT_INSTALL_DEV_TOOLS:-true}"
export COMPOSE_PROGRESS="${COMPOSE_PROGRESS:-plain}"
export BUILDKIT_PROGRESS="${BUILDKIT_PROGRESS:-plain}"

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  printf '\nERREUR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Commande manquante: $1"
}

require_docker_ready() {
  need_cmd docker
  if ! timeout 15 docker version >/dev/null 2>&1; then
    die "Docker ne répond pas dans WSL. Vérifie que le daemon Docker est démarré, puis relance la commande. Exemple: sudo service docker start"
  fi
}

require_linux() {
  [ "$(uname -s)" = "Linux" ] || die "Ces scripts doivent être lancés dans WSL/Ubuntu, pas dans PowerShell."
}

require_repo_dirs() {
  [ -d "$ORMT_INFRA_DIR" ] || die "Dossier infra introuvable: $ORMT_INFRA_DIR. Lance ./install-wsl-stage.sh."
  [ -d "$ORMT_API_DIR" ] || die "Dossier API introuvable: $ORMT_API_DIR. Lance ./install-wsl-stage.sh."
  [ -d "$ORMT_WEB_DIR" ] || die "Dossier web introuvable: $ORMT_WEB_DIR. Lance ./install-wsl-stage.sh."
}

clone_if_missing() {
  local dir="$1"
  local url="$2"
  local name="$3"
  local branch="${4:-}"

  if [ -d "$dir/.git" ]; then
    log "$name deja present: $dir"
    if [ -n "$branch" ]; then
      log "Synchronisation de $name sur la branche $branch"
      (
        cd "$dir"
        if [ -n "$(git status --porcelain)" ]; then
          die "$name contient des modifications locales. Commit ou stash requis avant le changement vers $branch."
        fi
        git fetch origin "$branch"
        if git show-ref --verify --quiet "refs/heads/$branch"; then
          git checkout "$branch"
        else
          git checkout -b "$branch" --track "origin/$branch"
        fi
        git pull --ff-only origin "$branch"
      )
    fi
    return
  fi

  if [ -e "$dir" ]; then
    die "$name existe mais ce n'est pas un dépôt Git valide: $dir"
  fi

  if [ -n "$branch" ]; then
    log "Clonage $name (branche $branch)"
    git clone --branch "$branch" --single-branch "$url" "$dir"
  else
    log "Clonage $name"
    git clone "$url" "$dir"
  fi
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

  log "Attente: $name"
  until curl --fail --silent --show-error "$url" >/dev/null 2>&1; do
    attempts=$((attempts - 1))
    [ "$attempts" -gt 0 ] || {
      log "Diagnostic Docker apres echec de $name"
      docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' >&2 || true
      die "$name indisponible apres le delai d'attente: $url"
    }
    sleep 2
  done
  log "OK: $name"
}

wait_for_host_route() {
  local name="$1"
  local host="$2"
  local path="$3"
  local attempts="${4:-60}"

  log "Attente: $name"
  until curl --fail --silent --show-error --header "Host: $host" "http://127.0.0.1$path" >/dev/null 2>&1; do
    attempts=$((attempts - 1))
    [ "$attempts" -gt 0 ] || {
      log "Diagnostic Docker apres echec de $name"
      docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' >&2 || true
      die "$name indisponible apres le delai d'attente: http://$host$path"
    }
    sleep 2
  done
  log "OK: $name"
}

wait_for_container_health() {
  local container="$1"
  local attempts="${2:-60}"

  log "Attente healthcheck: $container"
  until [ "$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || true)" = "healthy" ]; do
    attempts=$((attempts - 1))
    [ "$attempts" -gt 0 ] || {
      docker logs --tail 80 "$container" 2>/dev/null || true
      die "$container n'est pas healthy"
    }
    sleep 2
  done
}

verify_proxy() {
  docker network inspect proxy >/dev/null 2>&1 || die "Le réseau Docker externe 'proxy' n'existe pas. Lance ./install-wsl-stage.sh."

  local proxy_container
  proxy_container="$(docker ps --format '{{.Names}}|{{.Image}}' | awk -F'|' 'tolower($2) ~ /traefik/ {print $1; exit}')"
  [ -n "$proxy_container" ] || die "Aucun conteneur Traefik actif trouvé."

  docker network connect proxy "$proxy_container" >/dev/null 2>&1 || true
  log "Proxy partagé détecté: $proxy_container"
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
