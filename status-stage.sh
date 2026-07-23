#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/common.sh"

require_linux
require_docker_ready
need_cmd curl

log "Conteneurs"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

log "Réseau proxy"
docker network inspect proxy >/dev/null 2>&1 && echo "OK: réseau proxy présent" || echo "KO: réseau proxy absent"

check_route() {
  local name="$1"
  local host="$2"
  local path="$3"
  local code
  code="$(curl --silent --output /dev/null --write-out '%{http_code}' --header "Host: $host" "http://127.0.0.1$path" || true)"
  printf '%-35s HTTP %s\n' "$name" "$code"
}

check_url() {
  local name="$1"
  local url="$2"
  local code
  code="$(curl --silent --output /dev/null --write-out '%{http_code}' "$url" || true)"
  printf '%-35s HTTP %s\n' "$name" "$code"
}

log "Routes"
check_route "Traefik" "traefik.localhost" "/"
check_route "Frontend" "ormt-web.localhost" "/"
check_route "API Swagger" "ormt-core-api.localhost" "/v3/api-docs"
check_route "API Partenaires" "ormt-core-api.localhost" "/api/v1/public/partenaires"
check_route "Nextcloud" "ormt-nextcloud.localhost" "/status.php"
check_url "Keycloak" "http://127.0.0.1:8092/realms/master"
check_url "MinIO" "http://127.0.0.1:9000/minio/health/live"
