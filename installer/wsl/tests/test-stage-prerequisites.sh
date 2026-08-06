#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_linux
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

check_container() {
  local label="$1"
  local container="$2"
  check "$label" test "$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || true)" = "running"
}

check_route() {
  local label="$1"
  local host="$2"
  local code
  code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --header "Host: $host" http://127.0.0.1/ 2>/dev/null || true)"
  if [[ "$code" =~ ^(200|301|302|401|403|404)$ ]]; then
    printf '  [OK] %-30s HTTP %s\n' "$label" "$code"
  else
    printf '  [KO] %-30s HTTP %s\n' "$label" "${code:-000}" >&2
    failures=$((failures + 1))
  fi
}

log "Validation du socle minimal requis par le Stage"
check "systemd actif" bash -c "systemctl show --property=SystemState --value | grep -Eq '^(running|degraded)$'"
check "Docker répond" timeout 15 docker version
check "Docker Compose disponible" docker compose version
check "Utilisateur dans le groupe docker" bash -c "id -nG | tr ' ' '\n' | grep -qx docker"
check "Docker accessible sans sudo" docker ps
check "Réseau proxy présent" docker network inspect proxy
check_container "Traefik actif" traefik
check_route "Route Traefik" traefik.ormt.local

if test "$failures" -ne 0; then
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' >&2 || true
  die "$failures prérequis Stage en échec. Aucune donnée métier n'a été supprimée."
fi

log "Socle minimal du Stage validé"
