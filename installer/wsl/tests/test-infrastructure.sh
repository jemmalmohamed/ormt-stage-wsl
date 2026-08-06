#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

require_linux
failures=0

if ! command -v docker >/dev/null 2>&1; then
  printf '  [INFO] Infrastructure non installée : Docker est absent.\n'
  exit 1
fi

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  [OK] %s\n' "$label"
  else
    printf '  [KO] %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

check_container() {
  local label="$1"
  local container="$2"
  check "$label" test "$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || true)" = "running"
}

check_route() {
  local label="$1"
  local host="$2"
  local expected="${3:-200|301|302|401|403|404}"
  local code
  code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --header "Host: $host" http://127.0.0.1/ 2>/dev/null || true)"
  if [[ "$code" =~ ^($expected)$ ]]; then
    printf '  [OK] %-30s HTTP %s\n' "$label" "$code"
  else
    printf '  [KO] %-30s HTTP %s\n' "$label" "${code:-000}" >&2
    failures=$((failures + 1))
  fi
}

log "Validation de l'infrastructure WSL"
check "systemd actif" bash -c "systemctl show --property=SystemState --value | grep -Eq '^(running|degraded)$'"
check "Docker répond" timeout 15 docker version
check "Docker Compose disponible" docker compose version
check "Utilisateur dans le groupe docker" bash -c "id -nG | tr ' ' '\n' | grep -qx docker"
check "Docker accessible sans sudo" docker ps
check "Réseau proxy présent" docker network inspect proxy
check_container "Traefik actif" traefik
check_route "Route Traefik" proxy.ormt.localhost

if test "$ORMT_INSTALL_DEV_TOOLS" = "true"; then
  check_container "Portainer actif" portainer
  check_container "Jenkins actif" jenkins
  check_container "Homepage actif" homepage
  check_container "Grafana actif" grafana
  check_container "Prometheus actif" prometheus
  check_container "cAdvisor actif" cadvisor
  check_container "Node Exporter actif" node_exporter
  check_route "Route Portainer" containers.ormt.localhost
  check_route "Route Jenkins" jenkins.ormt.localhost
  check_route "Route Homepage" homepage.ormt.localhost
  check_route "Route Grafana" grafana.ormt.localhost
  check_route "Route Prometheus" prometheus.ormt.localhost
fi

if test "$failures" -ne 0; then
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' >&2 || true
  die "$failures contrôle(s) infrastructure en échec. Stage bloqué."
fi

log "Infrastructure complète validée"
