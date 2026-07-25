#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/docker.sh"

log "Réparation non destructive des services"
ensure_docker_service

if "$WSL_ROOT/tests/test-infrastructure.sh"; then
  mark_state infrastructure-validated
else
  clear_state infrastructure-validated
  exit 10
fi

if "$WSL_ROOT/tests/test-stage.sh"; then
  mark_state stage-validated
  exit 0
fi

clear_state stage-validated
exit 11

