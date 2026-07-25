#!/usr/bin/env bash

STATE_DIR="${ORMT_STATE_DIR:-${HOME}/.local/state/ormt-stage}"
STATE_ENV="${STATE_DIR}/.env"
STATE_SOURCE_ENV="${STATE_DIR}/source.env"
STATE_MARKERS="${STATE_DIR}/markers"
STATE_BUILDS="${STATE_DIR}/builds"

init_state() {
  mkdir -p "$STATE_DIR" "$STATE_MARKERS" "$STATE_BUILDS"
  chmod 700 "$STATE_DIR" 2>/dev/null || true
}

mark_state() {
  local name="$1"
  local value="${2:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}"
  printf '%s\n' "$value" > "${STATE_MARKERS}/${name}"
}

clear_state() {
  local name="$1"
  rm -f "${STATE_MARKERS:?}/${name}"
}

has_state() {
  test -f "${STATE_MARKERS}/${1}"
}

state_value() {
  local name="$1"
  test -f "${STATE_MARKERS}/${name}" && cat "${STATE_MARKERS}/${name}"
}

build_is_current() {
  local name="$1"
  local fingerprint="$2"
  test -f "${STATE_BUILDS}/${name}" &&
    test "$(cat "${STATE_BUILDS}/${name}")" = "$fingerprint"
}

mark_build() {
  local name="$1"
  local fingerprint="$2"
  printf '%s\n' "$fingerprint" > "${STATE_BUILDS}/${name}"
}
