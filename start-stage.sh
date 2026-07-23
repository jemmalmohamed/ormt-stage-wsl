#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/common.sh"

require_linux
require_repo_dirs
require_docker_ready
need_cmd curl
need_cmd mvn

verify_proxy

log "Démarrage PostgreSQL ORMT"
compose_up "$ORMT_API_DIR" \
  --env-file ./docker/services/postgres/env/.env.stage \
  -f ./docker/services/postgres/docker-compose.postgres.base.yml \
  -f ./docker/services/postgres/docker-compose.postgres.stage.yml

log "Démarrage Keycloak"
compose_up "$ORMT_API_DIR" \
  --env-file ./docker/services/keycloak/env/.env.stage \
  -f ./docker/services/keycloak/docker-compose.kc.base.yml \
  -f ./docker/services/keycloak/docker-compose.kc.stage.yml

log "Démarrage MinIO"
compose_up "$ORMT_API_DIR" \
  --env-file ./docker/services/minio/env/.env.stage \
  -f ./docker/services/minio/docker-compose.minio.base.yml \
  -f ./docker/services/minio/docker-compose.minio.stage.yml

log "Démarrage Nextcloud"
compose_up "$ORMT_API_DIR" \
  --env-file ./docker/services/nextcloud/env/.env.stage \
  -f ./docker/services/nextcloud/docker-compose.nextcloud.base.yml \
  -f ./docker/services/nextcloud/docker-compose.nextcloud.stage.yml

wait_for_container_health ormt-database 60
wait_for_url "MinIO" "http://127.0.0.1:9000/minio/health/live" 60
wait_for_url "Keycloak" "http://127.0.0.1:8092/realms/master" 60
wait_for_host_route "Nextcloud" "ormt-nextcloud.localhost" "/status.php" 90

log "Compilation des APIs"
MVN_ARGS=(clean install)
if [ "$ORMT_SKIP_TESTS" = "true" ]; then
  MVN_ARGS+=( -DskipTests )
fi
(cd "$ORMT_API_DIR" && sh scripts/verify-separation.sh)
(cd "$ORMT_API_DIR" && mvn -f ormt-core-api/pom.xml "${MVN_ARGS[@]}")
(cd "$ORMT_API_DIR" && mvn -f ormt-content-api/pom.xml "${MVN_ARGS[@]}")

log "Construction des images API"
(cd "$ORMT_API_DIR" && docker build -f ormt-core-api/Dockerfile -t ormt/ormt-core-api:latest ormt-core-api)
(cd "$ORMT_API_DIR" && docker build -f ormt-content-api/Dockerfile -t ormt/ormt-content-api:latest ormt-content-api)

log "Démarrage des APIs"
mapfile -t API_COMPOSE_ARGS < <(api_service_compose_args)
(cd "$ORMT_API_DIR" && docker compose "${API_COMPOSE_ARGS[@]}" up -d --force-recreate --remove-orphans)

wait_for_host_route "ormt-core-api /v3/api-docs" "ormt-core-api.localhost" "/v3/api-docs" 90
wait_for_host_route "ormt-content-api /api/v1/public/partenaires" "ormt-core-api.localhost" "/api/v1/public/partenaires" 90

log "Construction de l'image frontend Stage"
(cd "$ORMT_WEB_DIR" && docker build --build-arg ENV=stage --tag ormt/ormt-web-stage:latest .)

log "Démarrage du frontend Stage"
compose_up "$ORMT_WEB_DIR" \
  --env-file ./docker/app/env/.env.stage \
  -f ./docker/app/docker-compose.ormt-web.stage.yml \
  --project-name ormt-web-stage

wait_for_container_health ormt-web-stage 60
wait_for_host_route "Frontend Stage" "ormt-web.localhost" "/" 60

cat <<'MSG'

Stage démarré.

URLs principales:
  Frontend : http://ormt-web.localhost
  API      : http://ormt-core-api.localhost/api/v1
  Keycloak : http://localhost:8092
  MinIO    : http://localhost:9000

Diagnostic:
  ./status-stage.sh
MSG
