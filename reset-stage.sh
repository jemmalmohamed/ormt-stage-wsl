#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/common.sh"

require_linux
require_repo_dirs
require_docker_ready

cat <<'MSG'
ATTENTION: cette commande supprime les conteneurs et les volumes ORMT Stage.
Le proxy Traefik partagé est conservé.
MSG

read -r -p "Tape RESET pour continuer: " CONFIRMATION
[ "$CONFIRMATION" = "RESET" ] || die "Réinitialisation annulée."

log "Suppression frontend"
compose_down "$ORMT_WEB_DIR" \
  --env-file ./docker/app/env/.env.stage \
  -f ./docker/app/docker-compose.ormt-web.stage.yml \
  --project-name ormt-web-stage || true
docker rm --force ormt-web-stage ormt-web >/dev/null 2>&1 || true
docker rmi --force ormt/ormt-web-stage:latest ormt/ormt-web:latest >/dev/null 2>&1 || true

log "Suppression APIs"
mapfile -t API_COMPOSE_ARGS < <(api_service_compose_args)
compose_down_volumes "$ORMT_API_DIR" "${API_COMPOSE_ARGS[@]}" || true
docker rm --force ormt-api content-service >/dev/null 2>&1 || true
docker rmi --force ormt/ormt-core-api:latest ormt/ormt-content-api:latest ormt/ormt-api:latest ormt/content-service:latest >/dev/null 2>&1 || true

log "Suppression PostgreSQL, Keycloak, MinIO, Nextcloud"
compose_down_volumes "$ORMT_API_DIR" \
  --env-file ./docker/services/postgres/env/.env.stage \
  -f ./docker/services/postgres/docker-compose.postgres.base.yml \
  -f ./docker/services/postgres/docker-compose.postgres.stage.yml || true
compose_down_volumes "$ORMT_API_DIR" \
  --env-file ./docker/services/keycloak/env/.env.stage \
  -f ./docker/services/keycloak/docker-compose.kc.base.yml \
  -f ./docker/services/keycloak/docker-compose.kc.stage.yml || true
compose_down_volumes "$ORMT_API_DIR" \
  --env-file ./docker/services/minio/env/.env.stage \
  -f ./docker/services/minio/docker-compose.minio.base.yml \
  -f ./docker/services/minio/docker-compose.minio.stage.yml || true
compose_down_volumes "$ORMT_API_DIR" \
  --env-file ./docker/services/nextcloud/env/.env.stage \
  -f ./docker/services/nextcloud/docker-compose.nextcloud.base.yml \
  -f ./docker/services/nextcloud/docker-compose.nextcloud.stage.yml || true

echo "Réinitialisation terminée."
