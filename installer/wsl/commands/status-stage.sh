#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_linux
require_docker_ready

log "Conteneurs Docker"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

log "Validation infrastructure"
"$WSL_ROOT/tests/test-infrastructure.sh" || true

log "Validation Stage métier"
"$WSL_ROOT/tests/test-stage.sh" || true

