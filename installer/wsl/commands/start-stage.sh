#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/docker.sh"

require_linux
require_project_dirs
require_docker_ready
need_cmd curl
verify_proxy

mapfile -t api_args < <(api_service_compose_args)
(cd "$ORMT_API_DIR" && docker compose "${api_args[@]}" config --quiet)

set_progress "Services métier — téléchargement parallèle des images Docker"
log "Préchargement parallèle des images des services métier"
prefetch_docker_images \
  "$ORMT_API_DIR/docker/services" \
  "${ORMT_DOCKER_PULL_PARALLEL:-4}"

set_progress "Services métier — démarrage PostgreSQL, Keycloak, MinIO et Nextcloud"
log "Démarrage PostgreSQL, Keycloak, MinIO et Nextcloud"
compose_up "$ORMT_API_DIR" \
  --env-file ./docker/services/postgres/env/.env.stage \
  -f ./docker/services/postgres/docker-compose.postgres.base.yml \
  -f ./docker/services/postgres/docker-compose.postgres.stage.yml
compose_up "$ORMT_API_DIR" \
  --env-file ./docker/services/keycloak/env/.env.stage \
  -f ./docker/services/keycloak/docker-compose.kc.base.yml \
  -f ./docker/services/keycloak/docker-compose.kc.stage.yml
compose_up "$ORMT_API_DIR" \
  --env-file ./docker/services/minio/env/.env.stage \
  -f ./docker/services/minio/docker-compose.minio.base.yml \
  -f ./docker/services/minio/docker-compose.minio.stage.yml
compose_up "$ORMT_API_DIR" \
  --env-file ./docker/services/nextcloud/env/.env.stage \
  -f ./docker/services/nextcloud/docker-compose.nextcloud.base.yml \
  -f ./docker/services/nextcloud/docker-compose.nextcloud.stage.yml

wait_for_container_health ormt-database 60
wait_for_container_health minio-ormt 60
wait_for_host_route "Keycloak (realm master)" "keycloak.ormt.local" "/realms/master" 90
wait_for_host_route "Nextcloud" "nextcloud.ormt.local" "/status.php" 90

api_fingerprint="$(source_fingerprint "$ORMT_API_DIR")"
if build_is_current api "$api_fingerprint" && api_image_exists; then
  log "Images API inchangées: reconstruction ignorée"
else
  maven_args=(-B package)
  if test "$ORMT_SKIP_TESTS" = "true"; then
    maven_args=(-B -DskipTests package)
  fi

  set_progress "API Core + Content — compilation Maven parallèle avec cache partagé"
  log "Compilation parallèle des API Core et Content (cache Maven partagé)"
  (
    cd "$ORMT_API_DIR/ormt-core-api"
    bash ./mvnw "${maven_args[@]}"
  ) &
  core_pid=$!
  (
    cd "$ORMT_API_DIR/ormt-content-api"
    bash ./mvnw "${maven_args[@]}"
  ) &
  content_pid=$!

  core_status=0
  content_status=0
  wait "$core_pid" || core_status=$?
  wait "$content_pid" || content_status=$?
  if test "$core_status" -ne 0 || test "$content_status" -ne 0; then
    die "Échec de compilation Maven (Core=$core_status, Content=$content_status)"
  fi

  core_jar="$ORMT_API_DIR/ormt-core-api/target/ormt-core-api.jar"
  mapfile -t content_jars < <(find "$ORMT_API_DIR/ormt-content-api/target" -maxdepth 1 \
    -type f -name 'ormt-content-api-*.jar' -print)
  test -s "$core_jar" || die "JAR Core absent après compilation: $core_jar"
  test "${#content_jars[@]}" -eq 1 ||
    die "Un seul JAR Content était attendu, trouvé: ${#content_jars[@]}"
  test -s "${content_jars[0]}" || die "JAR Content vide: ${content_jars[0]}"

  runtime_context_root="$(mktemp -d)"
  trap 'rm -rf "$runtime_context_root"' EXIT
  mkdir -p "$runtime_context_root/core" "$runtime_context_root/content"
  cp "$core_jar" "$runtime_context_root/core/app.jar"
  cp "${content_jars[0]}" "$runtime_context_root/content/app.jar"

  set_progress "API Core + Content — création parallèle des images Docker d'exécution"
  log "Création parallèle des images d'exécution API"
  docker build \
    --file "$WSL_ROOT/templates/ormt-core-api.runtime.Dockerfile" \
    --tag ormt/ormt-core-api:latest \
    "$runtime_context_root/core" &
  core_image_pid=$!
  docker build \
    --file "$WSL_ROOT/templates/ormt-content-api.runtime.Dockerfile" \
    --tag ormt/ormt-content-api:latest \
    "$runtime_context_root/content" &
  content_image_pid=$!

  core_image_status=0
  content_image_status=0
  wait "$core_image_pid" || core_image_status=$?
  wait "$content_image_pid" || content_image_status=$?
  if test "$core_image_status" -ne 0 || test "$content_image_status" -ne 0; then
    die "Échec de création des images Docker (Core=$core_image_status, Content=$content_image_status)"
  fi
  rm -rf "$runtime_context_root"
  trap - EXIT
  mark_build api "$api_fingerprint"
fi

set_progress "API Core + Content — création et démarrage des conteneurs"
log "Démarrage des APIs"
(cd "$ORMT_API_DIR" &&
  docker compose "${api_args[@]}" up -d --force-recreate --remove-orphans)

wait_for_host_route "API Core" "api.ormt.local" "/v3/api-docs" 90
wait_for_host_route "Keycloak (realm ORMT configuré par Core API)" "keycloak.ormt.local" "/realms/ormt" 90
wait_for_host_route "API Content" "content-api.ormt.local" "/api/v1/public/partenaires" 90
wait_for_host_route "API Content Publications" "content-api.ormt.local" "/api/v1/public/publications?pageSize=1" 90

web_fingerprint="$(source_fingerprint "$ORMT_WEB_DIR")"
if build_is_current web "$web_fingerprint" && web_image_exists; then
  log "Image frontend inchangée: reconstruction ignorée"
else
  set_progress "Frontend Stage — installation npm et compilation Angular"
  log "Construction du frontend Stage"
  (cd "$ORMT_WEB_DIR" &&
    docker build --build-arg ENV=stage \
      --tag ormt/ormt-web-stage:latest .)
  mark_build web "$web_fingerprint"
fi

set_progress "Frontend Stage — démarrage du conteneur"
log "Démarrage du frontend"
if docker container inspect ormt-web-stage >/dev/null 2>&1; then
  log "Ancien conteneur frontend détecté: recréation sans suppression de données"
  docker container rm --force ormt-web-stage >/dev/null
fi
compose_up "$ORMT_WEB_DIR" \
  --env-file ./docker/app/env/.env.stage \
  -f ./docker/app/docker-compose.ormt-web.stage.yml \
  --project-name ormt-web-stage

wait_for_container_health ormt-web-stage 60
wait_for_host_route "Frontend Stage" "ormt.local" "/" 60
clear_progress

cat <<'MSG'

Stage démarré.
  Frontend : http://ormt.local
  API Core : http://api.ormt.local/api/v1
  API Content : http://content-api.ormt.local/api/v1
  Keycloak : http://keycloak.ormt.local
  MinIO    : http://minio.ormt.local
MSG
