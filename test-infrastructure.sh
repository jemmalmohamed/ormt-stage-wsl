#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/common.sh"

require_linux
require_repo_dirs
require_docker_ready
need_cmd git
need_cmd curl
need_cmd mvn

failures=0

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  [OK] %s\n' "$label"
  else
    printf '  [KO] %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

log "Test de l'infrastructure WSL"
check "Docker repond" timeout 15 docker version
check "Docker Compose disponible" docker compose version
check "Reseau proxy present" docker network inspect proxy
check "Traefik actif" bash -c "docker ps --format '{{.Image}}' | grep -qi traefik"
check "Depot infrastructure present" test -d "$ORMT_INFRA_DIR/.git"
check "Depot API present" test -d "$ORMT_API_DIR/.git"
check "Depot frontend present" test -d "$ORMT_WEB_DIR/.git"

if [ "$failures" -ne 0 ]; then
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true
  die "$failures test(s) d'infrastructure en echec. Stage ne sera pas lance."
fi

log "Infrastructure validee: tous les controles sont OK"
