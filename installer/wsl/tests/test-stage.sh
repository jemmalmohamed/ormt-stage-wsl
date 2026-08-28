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

check_container_env_absent() {
  local label="$1"
  local container="$2"
  local prefix="$3"
  if docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2>/dev/null |
    grep --quiet "^${prefix}"; then
    printf '  [KO] %-28s variable interdite %s* présente\n' "$label" "$prefix" >&2
    failures=$((failures + 1))
  else
    printf '  [OK] %-28s aucun secret %s*\n' "$label" "$prefix"
  fi
}

check_content_assets() {
  local partenaires publications image_keys publication_keys file_key code checked=0 missing=0
  partenaires="$(curl --silent --show-error --fail --header "Host: ormt-content-api.localhost" \
    http://127.0.0.1/api/v1/public/partenaires 2>/dev/null || true)"
  publications="$(curl --silent --show-error --fail --header "Host: ormt-content-api.localhost" \
    'http://127.0.0.1/api/v1/public/publications?pageSize=100' 2>/dev/null || true)"
  image_keys="$(printf '%s' "$partenaires" | grep --only-matching '"imageUrl":"[^"]*"' | sed 's/^"imageUrl":"//; s/"$//' || true)"
  publication_keys="$(printf '%s' "$publications" | grep --only-matching '"fichierUrl":"[^"]*"' | sed 's/^"fichierUrl":"//; s/"$//' || true)"

  if test -z "$image_keys" || test -z "$publication_keys"; then
    printf '  [KO] %-28s données Content initiales absentes\n' "Fichiers Content" >&2
    failures=$((failures + 1))
    return
  fi

  while IFS= read -r file_key; do
    test -n "$file_key" || continue
    checked=$((checked + 1))
    code="$(curl --silent --output /dev/null --write-out '%{http_code}' \
      --get --data-urlencode "fileKey=$file_key" \
      --header "Host: ormt-content-api.localhost" \
      http://127.0.0.1/api/v1/files/secure-url 2>/dev/null || true)"
    if test "$code" != "200"; then
      missing=$((missing + 1))
    fi
  done < <(printf '%s\n%s\n' "$image_keys" "$publication_keys")

  if test "$missing" -eq 0; then
    printf '  [OK] %-28s %s objet(s) MinIO vérifié(s)\n' "Fichiers Content" "$checked"
  else
    printf '  [KO] %-28s %s objet(s) absent(s) sur %s\n' "Fichiers Content" "$missing" "$checked" >&2
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
check_content_assets
check_http "Nextcloud" '200' --header "Host: nextcloud.ormt.localhost" http://127.0.0.1/status.php
check_http "Keycloak master" '200' --header "Host: users.ormt.localhost" http://127.0.0.1/realms/master
check_http "MinIO" '200' --header "Host: minio.ormt.localhost" http://127.0.0.1/minio/health/live
check_http "Keycloak ORMT" '200' http://127.0.0.1:8092/realms/ormt
check_http "MinIO" '200' http://127.0.0.1:9000/minio/health/live
check_container_env_absent "Core sans admin MinIO" ormt-core-api MINIO_ROOT_
check_container_env_absent "Content sans admin MinIO" ormt-content-api MINIO_ROOT_

if test "$failures" -ne 0; then
  docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' >&2 || true
  die "$failures test(s) Stage en échec."
fi

log "Stage validé: tous les tests sont OK"
