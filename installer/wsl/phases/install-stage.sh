#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

ORMT_STAGE_ACTION="${STAGE_ACTION:-deploy}" "$WSL_ROOT/commands/start-stage.sh"
"$WSL_ROOT/tests/test-stage.sh"
mark_state stage-validated
