#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/scripts/common.sh"

require_linux
need_cmd git

clone_if_missing \
  "$ORMT_INFRA_DIR" \
  "$ORMT_INFRA_REPO_URL" \
  "ormt-infra-stage-local-vps" \
  "$ORMT_INFRA_BRANCH"

clone_if_missing \
  "$ORMT_API_DIR" \
  "$ORMT_API_REPO_URL" \
  "ormt-api" \
  "$ORMT_API_BRANCH"

clone_if_missing \
  "$ORMT_WEB_DIR" \
  "$ORMT_WEB_REPO_URL" \
  "ormt-web-v1" \
  "$ORMT_WEB_BRANCH"

log "Depots synchronises"
printf '  API : %s (%s)\n' "$ORMT_API_DIR" "$(git -C "$ORMT_API_DIR" branch --show-current)"
printf '  Web : %s (%s)\n' "$ORMT_WEB_DIR" "$(git -C "$ORMT_WEB_DIR" branch --show-current)"
