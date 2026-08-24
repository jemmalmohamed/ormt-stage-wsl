#!/usr/bin/env bash
set -Eeuo pipefail

MODE="full"
SOURCE_MODE="auto"
LOG_FILE=""
PACKAGE_ROOT=""
PROVIDED_ROOT=""
RESET_STAGE=false
SELECT_GIT_BRANCHES=false

while test "$#" -gt 0; do
  case "$1" in
    --mode)
      MODE="${2:?Valeur --mode manquante}"
      shift 2
      ;;
    --source-mode)
      SOURCE_MODE="${2:?Valeur --source-mode manquante}"
      shift 2
      ;;
    --log-file)
      LOG_FILE="${2:?Valeur --log-file manquante}"
      shift 2
      ;;
    --package-root)
      PACKAGE_ROOT="${2:?Valeur --package-root manquante}"
      shift 2
      ;;
    --provided-sources-dir)
      PROVIDED_ROOT="${2:?Valeur --provided-sources-dir manquante}"
      shift 2
      ;;
    --reset-stage)
      RESET_STAGE=true
      shift
      ;;
    --select-git-branches)
      SELECT_GIT_BRANCHES=true
      shift
      ;;
    *)
      printf 'ERREUR: argument inconnu: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

MODE="${MODE,,}"
SOURCE_MODE="${SOURCE_MODE,,}"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CURRENT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET_ROOT="${HOME}/ormt-app/ormt-stage-wsl"

case "$MODE" in
  full|infrastructure|stage|diagnostic|repair) ;;
  *)
    printf 'ERREUR: mode invalide: %s\n' "$MODE" >&2
    exit 2
    ;;
esac

case "$SOURCE_MODE" in
  auto|provided|git) ;;
  *)
    printf 'ERREUR: mode source invalide: %s\n' "$SOURCE_MODE" >&2
    exit 2
    ;;
esac

if [[ "$CURRENT_ROOT" == /mnt/* ]]; then
  PACKAGE_ROOT="${PACKAGE_ROOT:-$CURRENT_ROOT}"
  PROVIDED_ROOT="${PROVIDED_ROOT:-${PACKAGE_ROOT}/sources}"
  printf '\n[%s] Synchronisation de l’installateur vers %s\n' "$(date '+%H:%M:%S')" "$TARGET_ROOT"
  incoming_installer="${TARGET_ROOT}/.installer.incoming.$$"
  previous_installer="${TARGET_ROOT}/.installer.previous"
  mkdir -p "$TARGET_ROOT" "$TARGET_ROOT/config"
  rm -rf "$incoming_installer"
  mkdir -p "$incoming_installer"
  cp -a "$CURRENT_ROOT/installer/." "$incoming_installer/"
  rm -rf "$previous_installer"
  if test -d "$TARGET_ROOT/installer"; then
    mv "$TARGET_ROOT/installer" "$previous_installer"
  fi
  mv "$incoming_installer" "$TARGET_ROOT/installer"
  rm -rf "$previous_installer"
  cp -a "$CURRENT_ROOT/config/." "$TARGET_ROOT/config/"
  cp -a "$CURRENT_ROOT/README.md" "$TARGET_ROOT/README.md" 2>/dev/null || true
  find "$TARGET_ROOT/installer/wsl" -type f -name '*.sh' -exec sed -i 's/\r$//' {} +
  chmod +x "$TARGET_ROOT/installer/wsl/setup.sh"
  find "$TARGET_ROOT/installer/wsl" -type f -name '*.sh' -exec chmod +x {} +
  reset_stage_args=()
  if test "$RESET_STAGE" = true; then
    reset_stage_args=(--reset-stage)
  fi
  branch_selection_args=()
  if test "$SELECT_GIT_BRANCHES" = true; then
    branch_selection_args=(--select-git-branches)
  fi
  exec "$TARGET_ROOT/installer/wsl/setup.sh" \
    --mode "$MODE" \
    --source-mode "$SOURCE_MODE" \
    --log-file "$LOG_FILE" \
    --package-root "$PACKAGE_ROOT" \
    --provided-sources-dir "$PROVIDED_ROOT" \
    "${branch_selection_args[@]}" \
    "${reset_stage_args[@]}"
fi

PACKAGE_ROOT="${PACKAGE_ROOT:-$CURRENT_ROOT}"
PROVIDED_ROOT="${PROVIDED_ROOT:-${PACKAGE_ROOT}/sources}"

if test -n "$LOG_FILE"; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(stdbuf -oL tee -a "$LOG_FILE") 2>&1
  LOG_TEE_PID=$!
  finish_logging() {
    local status=$?
    trap - EXIT
    exec 1>&- 2>&-
    wait "$LOG_TEE_PID" 2>/dev/null || true
    exit "$status"
  }
  trap finish_logging EXIT
fi

STATE_DIR="${HOME}/.local/state/ormt-stage"
STATE_ENV="${STATE_DIR}/.env"
ORMT_PROGRESS_FILE="${STATE_DIR}/current-progress"
export ORMT_PROGRESS_FILE
mkdir -p "$STATE_DIR"
rm -f "$ORMT_PROGRESS_FILE"

if test -f "$CURRENT_ROOT/config/.env"; then
  cp "$CURRENT_ROOT/config/.env" "$STATE_ENV"
elif ! test -f "$STATE_ENV"; then
  cp "$CURRENT_ROOT/config/.env.example" "$STATE_ENV"
fi
sed -i 's/\r$//' "$STATE_ENV"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/sources.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/docker.sh"

if test "$SELECT_GIT_BRANCHES" = true; then
  ORMT_SELECT_GIT_BRANCHES=true
fi
export ORMT_SELECT_GIT_BRANCHES

show_failure() {
  local status=$?
  local line="$1"
  local command="$2"
  printf '\n============================================================\n' >&2
  printf 'ÉCHEC DE L’INSTALLATION\n' >&2
  printf 'Mode        : %s\n' "$MODE" >&2
  printf 'Étape       : %s\n' "${CURRENT_STEP:-non déterminée}" >&2
  printf 'Commande    : %s\n' "$command" >&2
  printf 'Ligne       : %s\n' "$line" >&2
  printf 'Code erreur : %s\n' "$status" >&2
  printf 'Relance le même BAT pour reprendre sans supprimer les données.\n' >&2
  printf '============================================================\n' >&2
}
trap 'show_failure "$LINENO" "$BASH_COMMAND"' ERR

run_with_live_output() {
  local label="$1"
  shift
  CURRENT_STEP="$label"
  rm -f "${ORMT_PROGRESS_FILE:-}"
  local started=$SECONDS
  local status=0
  log "$label"
  "$@" || status=$?
  rm -f "${ORMT_PROGRESS_FILE:-}"
  if test "$status" -eq 0; then
    log "$label terminé en $((SECONDS - started))s"
    CURRENT_STEP=""
  fi
  return "$status"
}

prepare_environment() {
  local status=0
  CURRENT_STEP="Préparation de WSL"
  if "$SCRIPT_DIR/phases/prepare-wsl.sh"; then
    CURRENT_STEP=""
    return 0
  else
    status=$?
  fi
  case "$status" in
    42|43) exit "$status" ;;
    *) return "$status" ;;
  esac
}

sync_sources() {
  local scope
  case "$MODE" in
    infrastructure) scope="infrastructure" ;;
    stage) scope="stage" ;;
    full|repair) scope="all" ;;
    *) die "Le mode $MODE ne prépare pas de sources." ;;
  esac

  CURRENT_STEP="Préparation des sources"
  prepare_sources "$SOURCE_MODE" "$PROVIDED_ROOT" "$scope"
  CURRENT_STEP=""
}

ensure_infrastructure() {
  local reapply="${1:-false}"

  if ! command -v docker >/dev/null 2>&1; then
    log "Première installation détectée : Docker sera installé"
  elif test "$reapply" = "true"; then
    log "Réapplication de la configuration de l’infrastructure"
  elif "$SCRIPT_DIR/tests/test-infrastructure.sh"; then
    log "Infrastructure déjà installée et validée"
    mark_state infrastructure-installed "$ORMT_INSTALL_DEV_TOOLS"
    mark_state infrastructure-validated
    return 0
  fi

  clear_state infrastructure-validated
  local status=0
  if run_with_live_output "Installation de l’infrastructure" \
    "$SCRIPT_DIR/phases/install-infrastructure.sh"; then
    status=0
  else
    status=$?
  fi
  case "$status" in
    42|43) exit "$status" ;;
    0) ;;
    *) return "$status" ;;
  esac

  "$SCRIPT_DIR/tests/test-infrastructure.sh"
  mark_state infrastructure-validated
}

install_stage() {
  run_with_live_output "Installation du Stage métier" \
    "$SCRIPT_DIR/phases/install-stage.sh"
}

validate_stage_prerequisites() {
  CURRENT_STEP="Validation du socle minimal requis par le Stage"
  "$SCRIPT_DIR/tests/test-stage-prerequisites.sh"
  CURRENT_STEP=""
}

reset_stage_before_install() {
  test "$RESET_STAGE" = true || return 0
  printf '\n============================================================\n'
  printf 'ATTENTION — RÉINSTALLATION COMPLÈTE DU STAGE MÉTIER\n'
  printf 'Tous les conteneurs, volumes et données métier seront supprimés.\n'
  printf 'L’infrastructure partagée et Ubuntu WSL seront conservés.\n'
  printf '============================================================\n\n'
  if ! read -r -p "Tape exactement REINSTALLER pour continuer: " confirmation; then
    die "Confirmation interactive indisponible. Aucune donnée n'a été supprimée."
  fi
  if test "$confirmation" != "REINSTALLER"; then
    printf '\nRéinstallation du Stage annulée. Aucune donnée n’a été supprimée.\n'
    exit 44
  fi
  CURRENT_STEP="Suppression complète du Stage métier existant"
  "$SCRIPT_DIR/commands/reset-stage.sh" --yes
  CURRENT_STEP=""
}

diagnose() {
  CURRENT_STEP="Diagnostic infrastructure"
  "$SCRIPT_DIR/tests/test-infrastructure.sh"
  CURRENT_STEP="Diagnostic Stage métier"
  "$SCRIPT_DIR/tests/test-stage.sh"
  CURRENT_STEP=""
}

repair_installation() {
  ensure_infrastructure
  if "$SCRIPT_DIR/tests/test-stage.sh"; then
    log "Stage déjà fonctionnel"
    mark_state stage-validated
    return 0
  fi

  log "Tentative de redémarrage des conteneurs métier existants"
  docker start ormt-core-api ormt-content-api ormt-pdf-renderer ormt-web-stage >/dev/null 2>&1 || true
  sleep 15
  if "$SCRIPT_DIR/tests/test-stage.sh"; then
    log "Stage réparé sans reconstruction"
    mark_state stage-validated
    return 0
  fi

  clear_state stage-validated
  install_stage
}

started_at=$SECONDS
log "Mode: $MODE | Sources demandées: $SOURCE_MODE"

case "$MODE" in
  diagnostic)
    diagnose
    ;;
  infrastructure)
    prepare_environment
    sync_sources
    ensure_infrastructure true
    ;;
  stage)
    prepare_environment
    sync_sources
    validate_stage_prerequisites
    reset_stage_before_install
    install_stage
    ;;
  full)
    prepare_environment
    sync_sources
    ensure_infrastructure true
    install_stage
    ;;
  repair)
    prepare_environment
    sync_sources
    repair_installation
    ;;
esac

printf '\n============================================================\n'
printf 'SUCCÈS — mode %s validé\n' "$MODE"
printf 'Durée totale WSL: %ss\n' "$((SECONDS - started_at))"
printf '============================================================\n'
exit 0
