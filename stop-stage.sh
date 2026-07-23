#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/common.sh"

require_linux
require_repo_dirs
require_docker_ready

log "Arrêt du frontend"
compose_down "$ORMT_WEB_DIR" \
  --env-file ./docker/app/env/.env.stage \
  -f ./docker/app/docker-compose.ormt-web.stage.yml \
  --project-name ormt-web-stage || true

log "Arrêt des APIs"
mapfile -t API_COMPOSE_ARGS < <(api_service_compose_args)
compose_down "$ORMT_API_DIR" "${API_COMPOSE_ARGS[@]}" || true

log "Arrêt Nextcloud"
compose_down "$ORMT_API_DIR" \
  --env-file ./docker/services/nextcloud/env/.env.stage \
  -f ./docker/services/nextcloud/docker-compose.nextcloud.base.yml \
  -f ./docker/services/nextcloud/docker-compose.nextcloud.stage.yml || true

log "Arrêt MinIO"
compose_down "$ORMT_API_DIR" \
  --env-file ./docker/services/minio/env/.env.stage \
  -f ./docker/services/minio/docker-compose.minio.base.yml \
  -f ./docker/services/minio/docker-compose.minio.stage.yml || true

log "Arrêt Keycloak"
compose_down "$ORMT_API_DIR" \
  --env-file ./docker/services/keycloak/env/.env.stage \
  -f ./docker/services/keycloak/docker-compose.kc.base.yml \
  -f ./docker/services/keycloak/docker-compose.kc.stage.yml || true

log "Arrêt PostgreSQL ORMT"
compose_down "$ORMT_API_DIR" \
  --env-file ./docker/services/postgres/env/.env.stage \
  -f ./docker/services/postgres/docker-compose.postgres.base.yml \
  -f ./docker/services/postgres/docker-compose.postgres.stage.yml || true

echo "Stage arrêté sans suppression des volumes."
