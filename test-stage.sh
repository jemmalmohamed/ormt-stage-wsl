#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/common.sh"

require_linux
require_docker_ready
need_cmd curl

failures=0

check_http() {
  local label="$1"
  local expected="$2"
  shift 2
  local code
  if ! code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' "$@")"; then
    code="000"
  fi
  if [[ "$code" =~ ^($expected)$ ]]; then
    printf '  [OK] %-28s HTTP %s\n' "$label" "$code"
  else
    printf '  [KO] %-28s HTTP %s (attendu: %s)\n' "$label" "$code" "$expected" >&2
    failures=$((failures + 1))
  fi
}

log "Etat des conteneurs"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

log "Tests HTTP Stage"
check_http "Traefik" '200|301|302|404' --header "Host: traefik.localhost" http://127.0.0.1/
check_http "Frontend" '200|301|302' --header "Host: ormt-web.localhost" http://127.0.0.1/
check_http "API Swagger" '200' --header "Host: ormt-core-api.localhost" http://127.0.0.1/v3/api-docs
check_http "API Partenaires" '200' --header "Host: ormt-core-api.localhost" http://127.0.0.1/api/v1/public/partenaires
check_http "Nextcloud" '200' --header "Host: ormt-nextcloud.localhost" http://127.0.0.1/status.php
check_http "Keycloak" '200' http://127.0.0.1:8092/realms/master
check_http "MinIO" '200' http://127.0.0.1:9000/minio/health/live

if [ "$failures" -ne 0 ]; then
  log "Diagnostic des conteneurs en echec"
  docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' >&2 || true
  die "$failures test(s) Stage en echec."
fi

log "Stage valide: tous les tests sont OK"
