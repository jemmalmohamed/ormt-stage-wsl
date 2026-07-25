#!/usr/bin/env bash

validate_source_tree() {
  local root="$1"
  local failures=0
  local required=(
    "ormt-infra-stage-local-vps/ansible/all.playbook.yml"
    "ormt-api/ormt-core-api/pom.xml"
    "ormt-api/ormt-core-api/mvnw"
    "ormt-api/ormt-content-api/pom.xml"
    "ormt-api/ormt-content-api/mvnw"
    "ormt-api/docker/app/env/.env.stage"
    "ormt-api/docker/app/docker-compose.ormt-core-api.base.yml"
    "ormt-api/docker/app/docker-compose.ormt-content-api.base.yml"
    "ormt-web-v1/package.json"
    "ormt-web-v1/angular.json"
    "ormt-web-v1/Dockerfile"
    "ormt-web-v1/src/environments/environment.stage.ts"
  )
  local relative

  for relative in "${required[@]}"; do
    if ! test -e "$root/$relative"; then
      printf '  [MANQUANT] %s\n' "$relative" >&2
      failures=$((failures + 1))
    fi
  done
  test "$failures" -eq 0
}

copy_provided_project() {
  local source_dir="$1"
  local target_dir="$2"
  local name="$3"
  local managed_root
  local resolved_target
  local staging_dir
  local previous_dir
  local fingerprint
  local marker_name

  managed_root="$(realpath -m "${ORMT_WSL_WORKSPACE}/provided")"
  resolved_target="$(realpath -m "$target_dir")"
  case "$resolved_target" in
    "$managed_root"/*) ;;
    *) die "Destination fournie non sécurisée: $resolved_target" ;;
  esac

  staging_dir="${resolved_target}.incoming.$$"
  previous_dir="${resolved_target}.previous"
  marker_name="provided-${name,,}-fingerprint"
  fingerprint="$(source_fingerprint "$source_dir")"

  if test -d "$resolved_target" &&
    test "$(state_value "$marker_name" 2>/dev/null || true)" = "$fingerprint"; then
    log "Dossier fourni $name inchangé: copie ignorée"
    return 0
  fi

  log "Copie du dossier fourni $name vers WSL"
  rm -rf "$staging_dir"
  mkdir -p "$staging_dir"
  if ! (
    cd "$source_dir"
    tar \
      --exclude='.git' --exclude='*/.git' \
      --exclude='node_modules' --exclude='*/node_modules' \
      --exclude='target' --exclude='*/target' \
      --exclude='dist' --exclude='*/dist' \
      -cf - .
  ) | (cd "$staging_dir" && tar -xf -); then
    rm -rf "$staging_dir"
    die "La copie du dossier fourni $name a échoué. L'ancienne copie est conservée."
  fi

  rm -rf "$previous_dir"
  if test -e "$resolved_target"; then
    mv "$resolved_target" "$previous_dir"
  fi
  mv "$staging_dir" "$resolved_target"
  rm -rf "$previous_dir"
  mark_state "$marker_name" "$fingerprint"
}

activate_source_paths() {
  local mode="$1"
  local root
  if test "$mode" = "provided"; then
    root="${ORMT_WSL_WORKSPACE}/provided"
  else
    root="$ORMT_WSL_WORKSPACE"
  fi

  ORMT_INFRA_DIR="${root}/ormt-infra-stage-local-vps"
  ORMT_API_DIR="${root}/ormt-api"
  ORMT_WEB_DIR="${root}/ormt-web-v1"
  export ORMT_INFRA_DIR ORMT_API_DIR ORMT_WEB_DIR

  {
    printf 'ORMT_INFRA_DIR=%q\n' "$ORMT_INFRA_DIR"
    printf 'ORMT_API_DIR=%q\n' "$ORMT_API_DIR"
    printf 'ORMT_WEB_DIR=%q\n' "$ORMT_WEB_DIR"
  } > "$STATE_SOURCE_ENV"
}

normalize_build_wrappers() {
  local wrapper
  local wrappers=(
    "$ORMT_API_DIR/ormt-core-api/mvnw"
    "$ORMT_API_DIR/ormt-content-api/mvnw"
  )

  for wrapper in "${wrappers[@]}"; do
    test -f "$wrapper" || die "Wrapper Maven introuvable: $wrapper"
    sed -i 's/\r$//' "$wrapper"
  done
}

sync_provided_sources() {
  local root="$1"
  validate_source_tree "$root" ||
    die "Les dossiers fournis sont incomplets dans: $root"

  activate_source_paths provided
  mark_state source-mode provided
  mkdir -p "$(dirname "$ORMT_INFRA_DIR")"
  copy_provided_project "$root/ormt-infra-stage-local-vps" "$ORMT_INFRA_DIR" "infrastructure"
  copy_provided_project "$root/ormt-api" "$ORMT_API_DIR" "API"
  copy_provided_project "$root/ormt-web-v1" "$ORMT_WEB_DIR" "frontend"
}

sync_git_project() {
  local dir="$1"
  local url="$2"
  local branch="$3"
  local name="$4"

  if test -d "$dir/.git" && ! git -C "$dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    log "Nettoyage du clone incomplet de $name"
    rm -rf "$dir"
  fi

  if test -d "$dir/.git"; then
    test -z "$(git -C "$dir" status --porcelain)" ||
      die "$name contient des modifications locales: $dir"
    if test -n "$branch"; then
      log "Mise à jour de $name sur $branch"
      git -C "$dir" fetch --progress --depth 1 origin "$branch"
      if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$dir" checkout "$branch"
      else
        git -C "$dir" checkout -b "$branch" --track "origin/$branch"
      fi
      git -C "$dir" pull --ff-only --progress origin "$branch"
    else
      log "Mise à jour de $name"
      git -C "$dir" pull --ff-only --progress
    fi
  elif test -e "$dir"; then
    die "$name existe sans être un dépôt Git: $dir"
  elif test -n "$branch"; then
    log "Clonage de $name, branche $branch"
    git clone --progress --depth 1 --branch "$branch" --single-branch "$url" "$dir"
  else
    log "Clonage de $name"
    git clone --progress --depth 1 "$url" "$dir"
  fi

  printf '  %s: %s\n' "$name" "$(git -C "$dir" rev-parse --short HEAD)"
}

sync_git_sources() {
  if ! command -v git >/dev/null 2>&1; then
    log "Installation de Git requise pour récupérer les projets"
    sudo apt-get update
    sudo apt-get install -y git ca-certificates
  fi
  activate_source_paths git
  mkdir -p "$ORMT_WSL_WORKSPACE"
  sync_git_project "$ORMT_INFRA_DIR" "$ORMT_INFRA_REPO_URL" "$ORMT_INFRA_BRANCH" "Infrastructure"
  sync_git_project "$ORMT_API_DIR" "$ORMT_API_REPO_URL" "$ORMT_API_BRANCH" "API"
  sync_git_project "$ORMT_WEB_DIR" "$ORMT_WEB_REPO_URL" "$ORMT_WEB_BRANCH" "Frontend"
  mark_state source-mode git
}

resolve_source_mode() {
  local requested="${1,,}"
  local provided_root="$2"

  case "$requested" in
    provided)
      validate_source_tree "$provided_root" ||
        die "Le mode Provided exige les trois projets complets dans: $provided_root"
      printf 'provided\n'
      ;;
    git)
      printf 'git\n'
      ;;
    auto)
      if validate_source_tree "$provided_root" >/dev/null 2>&1; then
        printf 'provided\n'
      else
        printf 'git\n'
      fi
      ;;
    *)
      die "Mode source invalide: $requested"
      ;;
  esac
}

prepare_sources() {
  local requested="$1"
  local provided_root="$2"
  local selected
  selected="$(resolve_source_mode "$requested" "$provided_root")"
  log "Provenance des projets sélectionnée: $selected"

  case "$selected" in
    provided)
      sync_provided_sources "$provided_root"
      normalize_build_wrappers
      ;;
    git) sync_git_sources ;;
  esac
}
