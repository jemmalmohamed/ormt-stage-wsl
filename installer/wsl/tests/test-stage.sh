#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_linux
require_docker_ready
need_cmd curl
failures=0

check_container_health() {
  local label="$1"
  local container="$2"
  local health
  health="$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || true)"
  if test "$health" = "healthy"; then
    printf '  [OK] %-28s %s\n' "$label" "$health"
  else
    printf '  [KO] %-28s %s\n' "$label" "${health:-absent}" >&2
    failures=$((failures + 1))
  fi
}

check_http() {
  local label="$1"
  local expected="$2"
  shift 2
  local code
  code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' "$@" 2>/dev/null || true)"
  if [[ "$code" =~ ^($expected)$ ]]; then
    printf '  [OK] %-28s HTTP %s\n' "$label" "$code"
  else
    printf '  [KO] %-28s HTTP %s\n' "$label" "${code:-000}" >&2
    failures=$((failures + 1))
  fi
}

log "État des conteneurs Stage"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

log "Tests HTTP Stage"
check_container_health "Renderer PDF" ormt-pdf-renderer
check_http "Traefik" '200|301|302|404' --header "Host: proxy.ormt.localhost" http://127.0.0.1/
check_http "Frontend" '200|301|302' --header "Host: ormt.localhost" http://127.0.0.1/
check_http "API Swagger" '200' --header "Host: ormt-core-api.localhost" http://127.0.0.1/v3/api-docs
check_http "API Partenaires" '200' --header "Host: ormt-content-api.localhost" http://127.0.0.1/api/v1/public/partenaires
check_http "API Publications" '200' --header "Host: ormt-content-api.localhost" 'http://127.0.0.1/api/v1/public/publications?pageSize=1'
check_http "API Observatoire" '200' --header "Host: ormt-content-api.localhost" http://127.0.0.1/api/v1/public/observatoire-content/current
check_http "Nextcloud" '200' --header "Host: nextcloud.ormt.localhost" http://127.0.0.1/status.php
check_http "Keycloak master" '200' --header "Host: users.ormt.localhost" http://127.0.0.1/realms/master
check_http "MinIO" '200' --header "Host: minio.ormt.localhost" http://127.0.0.1/minio/health/live
check_http "Keycloak ORMT" '200' http://127.0.0.1:8092/realms/ormt
check_http "MinIO" '200' http://127.0.0.1:9000/minio/health/live

if test "$failures" -ne 0; then
  docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' >&2 || true
  die "$failures test(s) Stage en échec."
fi

log "Stage validé: tous les tests sont OK"
