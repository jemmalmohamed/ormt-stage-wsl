#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

SCOPE="stage"
LOG_FILE=""

while test "$#" -gt 0; do
  case "$1" in
    --scope)
      SCOPE="${2:?Valeur --scope manquante}"
      shift 2
      ;;
    --log-file)
      LOG_FILE="${2:?Valeur --log-file manquante}"
      shift 2
      ;;
    *)
      die "Argument inconnu pour le test après redémarrage: $1"
      ;;
  esac
done

case "$SCOPE" in
  infrastructure|stage) ;;
  *) die "Périmètre de validation invalide: $SCOPE" ;;
esac

if test -n "$LOG_FILE"; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(stdbuf -oL tee -a "$LOG_FILE") 2>&1
fi

log "Validation après redémarrage WSL — périmètre: $SCOPE"

docker_ready=false
for attempt in $(seq 1 30); do
  if timeout 10 docker version >/dev/null 2>&1; then
    docker_ready=true
    break
  fi
  printf '  Docker démarre — tentative %d/30\n' "$attempt"
  sleep 2
done
test "$docker_ready" = "true" || die "Docker ne répond pas après le redémarrage WSL."

if test "$SCOPE" = "stage"; then
  keycloak_ready=false
  for attempt in $(seq 1 60); do
    code="$(curl --silent --output /dev/null --write-out '%{http_code}' \
      http://127.0.0.1:8092/realms/ormt 2>/dev/null || true)"
    if test "$code" = "200"; then
      keycloak_ready=true
      break
    fi
    if test "$attempt" -eq 1 || test $((attempt % 5)) -eq 0; then
      printf '  Keycloak realm ORMT — HTTP %s — tentative %d/60\n' \
        "${code:-000}" "$attempt"
    fi
    sleep 2
  done
  test "$keycloak_ready" = "true" || die "Le realm Keycloak ORMT ne répond pas après redémarrage."

  log "Keycloak prêt — stabilisation des API"
  docker restart ormt-core-api ormt-content-api >/dev/null 2>&1 || true
fi

report_file="$(mktemp)"
trap 'rm -f "$report_file"' EXIT
validated=false

for attempt in $(seq 1 60); do
  : > "$report_file"
  if "$SCRIPT_DIR/test-infrastructure.sh" > "$report_file" 2>&1; then
    if test "$SCOPE" = "infrastructure" || \
      "$SCRIPT_DIR/test-stage.sh" >> "$report_file" 2>&1; then
      validated=true
      break
    fi
  fi

  if test "$attempt" -eq 1 || test $((attempt % 5)) -eq 0; then
    printf '  Services en cours de stabilisation — tentative %d/60\n' "$attempt"
  fi
  sleep 3
done

cat "$report_file"
if test "$validated" != "true"; then
  docker ps -a --format 'table {{.Names}}\t{{.Status}}' || true
  die "Validation après redémarrage WSL en échec."
fi

log "Redémarrage WSL validé: tous les services attendus sont opérationnels"
