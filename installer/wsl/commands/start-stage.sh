#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_linux
require_stage_project_dirs
require_docker_ready
need_cmd curl
verify_proxy

stage_action="${ORMT_STAGE_ACTION:-deploy}"
case "$stage_action" in
  deploy)
    api_action="DEPLOYER"
    api_restart_policy="always"
    ;;
  initialize)
    api_action="DEPLOYER_INITIALISER_DATA"
    api_restart_policy="no"
    ;;
  reinitialize)
    api_action="REINITIALISER_COMPLETEMENT"
    api_restart_policy="no"
    ;;
  *)
    die "Action Stage invalide: $stage_action (deploy, initialize ou reinitialize attendu)"
    ;;
esac

wait_for_application_ready_log() {
  local name="$1"
  local container="$2"
  local success_marker="$3"
  local attempts="${4:-900}"
  local total_attempts="$attempts"
  local status="unknown"

  log "Attente de la fin réelle: $name"
  while true; do
    if docker logs "$container" 2>&1 | grep --fixed-strings --quiet "$success_marker"; then
      clear_progress
      log "OK: $name terminé"
      return 0
    fi

    status="$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || true)"
    if [[ "$status" =~ ^(exited|dead|restarting)$ ]]; then
      docker logs --tail 200 "$container" 2>/dev/null || true
      die "$name a échoué (conteneur $container: ${status:-absent})"
    fi

    attempts=$((attempts - 1))
    if test "$attempts" -le 0; then
      docker logs --tail 200 "$container" 2>/dev/null || true
      die "$name n'est pas terminé après $((total_attempts * 2)) secondes"
    fi
    set_progress "$name — import en cours — tentative $((total_attempts - attempts))/$total_attempts"
    sleep 2
  done
}

validate_core_initial_data() {
  local stats=""
  stats="$(curl --silent --show-error --fail \
    --header "Host: ormt-core-api.localhost" \
    "http://127.0.0.1/api/v1/public/dashboard/stats" 2>/dev/null || true)"
  if ! grep --extended-regexp --quiet '"domaines":[1-9][0-9]*' <<< "$stats" ||
    ! grep --extended-regexp --quiet '"indicateurs":[1-9][0-9]*' <<< "$stats"; then
    docker logs --tail 200 ormt-core-api 2>/dev/null || true
    die "Initialisation Core incomplète: domaines ou indicateurs absents après l'import init-data"
  fi
  log "OK: données initiales Core présentes"
}

mapfile -t api_args < <(api_service_compose_args)
(cd "$ORMT_API_DIR" && docker compose "${api_args[@]}" config --quiet)

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
  --env-file ./docker/app/env/.env.stage \
  -f ./docker/services/minio/docker-compose.minio.base.yml \
  -f ./docker/services/minio/docker-compose.minio.stage.yml
compose_up "$ORMT_API_DIR" \
  --env-file ./docker/services/nextcloud/env/.env.stage \
  -f ./docker/services/nextcloud/docker-compose.nextcloud.base.yml \
  -f ./docker/services/nextcloud/docker-compose.nextcloud.stage.yml

wait_for_container_health ormt-database 60
wait_for_container_health minio-ormt 60

set_progress "MinIO — vérification du provisionnement"
log "Vérification du provisionnement MinIO"
if ! minio_bootstrap_status="$(timeout 120 docker wait ormt-minio-bootstrap)"; then
  docker logs --tail 200 ormt-minio-bootstrap 2>/dev/null || true
  die "Le provisionnement MinIO ne s'est pas terminé dans le délai attendu"
fi
if test "$minio_bootstrap_status" != "0"; then
  docker logs --tail 200 ormt-minio-bootstrap 2>/dev/null || true
  die "Le provisionnement MinIO a échoué (code $minio_bootstrap_status)"
fi
log "OK: buckets et compte applicatif MinIO provisionnés"

wait_for_host_route "Keycloak (realm master)" "users.ormt.localhost" "/realms/master" 90
wait_for_host_route "Nextcloud" "nextcloud.ormt.localhost" "/status.php" 90
log "Action Stage demandée: $stage_action (ORMT_ACTION=$api_action)"

api_fingerprint="$(source_fingerprint "$ORMT_API_DIR")"
if build_is_current api "$api_fingerprint" && api_image_exists; then
  log "Images API inchangées: reconstruction ignorée"
else
  set_progress "API Core + Content + Renderer PDF — construction parallèle des images officielles"
  log "Construction parallèle avec les mêmes Dockerfiles qu'en production"
  docker build \
    --build-arg SKIP_TESTS=true \
    --file "$ORMT_API_DIR/ormt-core-api/Dockerfile" \
    --tag ormt/ormt-core-api:latest \
    "$ORMT_API_DIR" &
  core_image_pid=$!
  docker build \
    --build-arg SKIP_TESTS=true \
    --file "$ORMT_API_DIR/ormt-content-api/Dockerfile" \
    --tag ormt/ormt-content-api:latest \
    "$ORMT_API_DIR" &
  content_image_pid=$!
  docker build \
    --file "$ORMT_API_DIR/ormt-pdf-renderer/Dockerfile" \
    --tag ormt/ormt-pdf-renderer:latest \
    "$ORMT_API_DIR" &
  renderer_image_pid=$!

  core_image_status=0
  content_image_status=0
  renderer_image_status=0
  wait "$core_image_pid" || core_image_status=$?
  wait "$content_image_pid" || content_image_status=$?
  wait "$renderer_image_pid" || renderer_image_status=$?
  if test "$core_image_status" -ne 0 ||
    test "$content_image_status" -ne 0 ||
    test "$renderer_image_status" -ne 0; then
    die "Échec de création des images Docker (Core=$core_image_status, Content=$content_image_status, Renderer=$renderer_image_status)"
  fi
  mark_build api "$api_fingerprint"
fi

set_progress "API Core + Content + Renderer PDF — création et démarrage des conteneurs"
log "Démarrage des API et du renderer PDF"
(cd "$ORMT_API_DIR" &&
  ORMT_ACTION="$api_action" API_RESTART_POLICY="$api_restart_policy" \
    docker compose "${api_args[@]}" up -d --force-recreate --remove-orphans)

wait_for_container_health ormt-pdf-renderer 60
if test "$stage_action" != "deploy"; then
  wait_for_application_ready_log "Initialisation API Core" ormt-core-api \
    "========== [CORE][DÉMARRAGE] FIN - SUCCÈS" 900
  wait_for_application_ready_log "Initialisation API Content" ormt-content-api \
    "========== [CONTENT][DÉMARRAGE] FIN - SUCCÈS" 300
fi
wait_for_host_route "API Core" "ormt-core-api.localhost" "/v3/api-docs" 90
wait_for_host_route "Keycloak (realm ORMT configuré par Core API)" "users.ormt.localhost" "/realms/ormt" 90
wait_for_host_route "API Content" "ormt-content-api.localhost" "/api/v1/public/partenaires" 90
wait_for_host_route "API Content Publications" "ormt-content-api.localhost" "/api/v1/public/publications?pageSize=1" 90

if test "$stage_action" != "deploy"; then
  validate_core_initial_data
  set_progress "API Core + Content — passage au mode de déploiement normal"
  log "Initialisation terminée: redémarrage définitif des API avec ORMT_ACTION=DEPLOYER"
  (cd "$ORMT_API_DIR" &&
    ORMT_ACTION=DEPLOYER API_RESTART_POLICY=always \
      docker compose "${api_args[@]}" up -d --force-recreate --no-deps ormt-core-api &&
    ORMT_ACTION=DEPLOYER API_RESTART_POLICY=always \
      docker compose "${api_args[@]}" up -d --force-recreate --no-deps ormt-content-api)
  wait_for_host_route "API Core après initialisation" "ormt-core-api.localhost" "/v3/api-docs" 90
  wait_for_host_route "API Content après initialisation" "ormt-content-api.localhost" "/api/v1/public/partenaires" 90
fi

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
(cd "$ORMT_WEB_DIR" && docker compose \
  --env-file ./docker/app/env/.env.stage \
  -f ./docker/app/docker-compose.ormt-web.stage.yml \
  --project-name ormt-web-stage \
  up -d --force-recreate --remove-orphans)

web_container_id="$(cd "$ORMT_WEB_DIR" && docker compose \
  --env-file ./docker/app/env/.env.stage \
  -f ./docker/app/docker-compose.ormt-web.stage.yml \
  --project-name ormt-web-stage \
  ps -q ormt-web-stage)"
test -n "$web_container_id" || die "Conteneur frontend Stage absent après docker compose up"
wait_for_container_health "$web_container_id" 60
wait_for_host_route "Frontend Stage" "ormt.localhost" "/" 60
clear_progress

cat <<'MSG'

Stage démarré.
  Frontend : http://ormt.localhost
  API Core : http://ormt-core-api.localhost/api/v1
  API Content : http://ormt-content-api.localhost/api/v1
  Keycloak : http://users.ormt.localhost
  MinIO    : http://minio.ormt.localhost
MSG
