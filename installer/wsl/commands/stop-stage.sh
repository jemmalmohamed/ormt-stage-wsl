#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_linux
require_stage_project_dirs
require_docker_ready

log "Arrêt du frontend"
compose_down "$ORMT_WEB_DIR" \
  --env-file ./docker/app/env/.env.stage \
  -f ./docker/app/docker-compose.ormt-web.stage.yml \
  --project-name ormt-web-stage || true

log "Arrêt des APIs"
mapfile -t api_args < <(api_service_compose_args)
compose_down "$ORMT_API_DIR" "${api_args[@]}" || true

for service in nextcloud minio keycloak postgres; do
  case "$service" in
    keycloak) base="kc" ;;
    *) base="$service" ;;
  esac
  log "Arrêt $service"
  compose_down "$ORMT_API_DIR" \
    --env-file "./docker/services/$service/env/.env.stage" \
    -f "./docker/services/$service/docker-compose.$base.base.yml" \
    -f "./docker/services/$service/docker-compose.$base.stage.yml" || true
done

clear_state stage-validated
printf '\nStage arrêté sans suppression des volumes.\n'
