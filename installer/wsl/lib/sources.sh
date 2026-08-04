#!/usr/bin/env bash

validate_source_tree() {
  local root="$1"
  local scope="${2:-all}"
  local failures=0
  local required=()
  local relative

  case "$scope" in
    infrastructure)
      required+=("ormt-infra-stage-local-vps/ansible/all.playbook.yml")
      ;;
    stage)
      required+=(
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
      ;;
    all)
      required+=(
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
      ;;
    *) die "Périmètre de sources invalide: $scope" ;;
  esac

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
  local scope="$2"
  validate_source_tree "$root" "$scope" ||
    die "Les dossiers fournis sont incomplets pour le périmètre $scope dans: $root"

  activate_source_paths provided
  mark_state source-mode provided
  mkdir -p "$(dirname "$ORMT_INFRA_DIR")"
  if test "$scope" = "infrastructure" || test "$scope" = "all"; then
    copy_provided_project "$root/ormt-infra-stage-local-vps" "$ORMT_INFRA_DIR" "infrastructure"
  fi
  if test "$scope" = "stage" || test "$scope" = "all"; then
    copy_provided_project "$root/ormt-api" "$ORMT_API_DIR" "API"
    copy_provided_project "$root/ormt-web-v1" "$ORMT_WEB_DIR" "frontend"
  fi
}

git_remote() {
  git -c credential.helper='cache --timeout=900' "$@"
}

sync_git_project() {
  local dir="$1"
  local url="$2"
  local branch="$3"
  local name="$4"
  local incomplete_backup=""
  local incomplete_root=""

  if test -d "$dir/.git" &&
    { ! git -C "$dir" rev-parse --verify HEAD >/dev/null 2>&1 ||
      ! test -f "$dir/.git/index"; }; then
    incomplete_root="$(dirname "$dir")/.incomplete"
    mkdir -p "$incomplete_root"
    incomplete_backup="${incomplete_root}/$(basename "$dir")-$(date '+%Y%m%d-%H%M%S')-$$"
    log "Clone incomplet de $name détecté: conservation dans $incomplete_backup"
    mv "$dir" "$incomplete_backup"
  fi

  if test -d "$dir/.git"; then
    test -z "$(git -C "$dir" status --porcelain)" ||
      die "$name contient des modifications locales: $dir"

    local target_ref=""
    if test -n "$branch"; then
      log "Mise à jour de $name sur $branch"
      local branch_refspec="+refs/heads/$branch:refs/remotes/origin/$branch"
      if ! git -C "$dir" config --get-all remote.origin.fetch |
        grep -Fxq "$branch_refspec"; then
        git -C "$dir" config --add remote.origin.fetch "$branch_refspec"
      fi
      if test "$(git -C "$dir" rev-parse --is-shallow-repository)" = "true"; then
        log "Approfondissement léger de l'historique Git superficiel"
        git_remote -C "$dir" fetch --progress --deepen 20 origin \
          "$branch_refspec"
      else
        git_remote -C "$dir" fetch --progress origin \
          "$branch_refspec"
      fi
      if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch"; then
        git -C "$dir" checkout "$branch"
      else
        git -C "$dir" checkout -b "$branch" --track "origin/$branch"
      fi
      target_ref="origin/$branch"
    else
      log "Mise à jour de $name"
      branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD)"
      test -n "$branch" || die "$name est positionné sur un commit détaché."
      if test "$(git -C "$dir" rev-parse --is-shallow-repository)" = "true"; then
        log "Approfondissement léger de l'historique Git superficiel"
        git_remote -C "$dir" fetch --progress --deepen 20 origin "$branch"
      else
        git_remote -C "$dir" fetch --progress origin "$branch"
      fi
      target_ref="origin/$branch"
    fi

    if git -C "$dir" merge-base --is-ancestor HEAD "$target_ref"; then
      git -C "$dir" merge --ff-only "$target_ref"
    elif git -C "$dir" merge-base --is-ancestor "$target_ref" HEAD; then
      log "$name contient des commits locaux supplémentaires; aucun écrasement effectué"
    else
      die "$name a réellement divergé de $target_ref. Les commits locaux sont conservés dans: $dir"
    fi
  elif test -e "$dir"; then
    die "$name existe sans être un dépôt Git: $dir"
  elif test -n "$branch"; then
    log "Clonage de $name, branche $branch"
    git_remote clone --progress --depth 20 --branch "$branch" --single-branch "$url" "$dir"
  else
    log "Clonage de $name"
    git_remote clone --progress --depth 20 "$url" "$dir"
  fi

  test -f "$dir/.git/index" ||
    die "Le clone de $name est incomplet (index Git absent): $dir"
  printf '  %s: %s\n' "$name" "$(git -C "$dir" rev-parse --short HEAD)"
}

select_git_branch() {
  local url="$1"
  local configured_branch="$2"
  local name="$3"
  local remote_default=""
  local selected=""
  local choice=""
  local index=0
  local branch=""
  local configured_available=false
  local remote_default_available=false
  local remote_query_ok=false
  local remote_heads=""
  local attempt=0
  local branches=()

  for attempt in 1 2 3; do
    if remote_heads="$(git_remote ls-remote --heads "$url" 2>&1)"; then
      remote_query_ok=true
      break
    fi
    if test "$attempt" -lt 3; then
      printf '  %s: accès GitHub impossible, nouvelle tentative %d/3 dans %ds\n' \
        "$name" "$((attempt + 1))" "$((attempt * 3))" >&2
      sleep "$((attempt * 3))"
    fi
  done

  if test "$remote_query_ok" != true; then
    printf '%s\n' "$remote_heads" >&2
    die "Impossible de consulter les branches de $name. Vérifie la connexion Internet et la résolution de github.com."
  fi

  mapfile -t branches < <(
    awk '{sub("refs/heads/", "", $2); print $2}' <<< "$remote_heads" |
      sort
  )
  test "${#branches[@]}" -gt 0 ||
    die "Aucune branche distante trouvée pour $name: $url"

  remote_default="$(
    { git_remote ls-remote --symref "$url" HEAD 2>/dev/null || true; } |
      awk '$1 == "ref:" {sub("refs/heads/", "", $2); print $2; exit}'
  )"

  for branch in "${branches[@]}"; do
    if test -n "$configured_branch" && test "$branch" = "$configured_branch"; then
      configured_available=true
    fi
    if test -n "$remote_default" && test "$branch" = "$remote_default"; then
      remote_default_available=true
    fi
  done

  if test "$configured_available" = true; then
    selected="$configured_branch"
  elif test "$remote_default_available" = true; then
    selected="$remote_default"
  else
    selected="${branches[0]}"
  fi

  if test "${#branches[@]}" -eq 1; then
    printf '  %s: une seule branche disponible (%s)\n' "$name" "${branches[0]}" >&2
    printf '%s\n' "${branches[0]}"
    return 0
  fi

  if ! test -t 0; then
    printf '  %s: entrée non interactive, branche %s sélectionnée\n' "$name" "$selected" >&2
    printf '%s\n' "$selected"
    return 0
  fi

  printf '\nBranches Git disponibles pour %s :\n' "$name" >&2
  for index in "${!branches[@]}"; do
    branch="${branches[$index]}"
    if test "$branch" = "$selected"; then
      printf '  %d. %s (par défaut)\n' "$((index + 1))" "$branch" >&2
    else
      printf '  %d. %s\n' "$((index + 1))" "$branch" >&2
    fi
  done

  while true; do
    printf 'Choisis la branche de %s [défaut: %s] : ' "$name" "$selected" >&2
    read -r choice
    if test -z "$choice"; then
      printf '%s\n' "$selected"
      return 0
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] &&
      test "$choice" -ge 1 && test "$choice" -le "${#branches[@]}"; then
      printf '%s\n' "${branches[$((choice - 1))]}"
      return 0
    fi
    printf 'Choix invalide. Saisis un numéro entre 1 et %d.\n' "${#branches[@]}" >&2
  done
}

sync_git_sources() {
  local scope="$1"
  local infra_branch="$ORMT_INFRA_BRANCH"
  local api_branch="$ORMT_API_BRANCH"
  local web_branch="$ORMT_WEB_BRANCH"
  if ! command -v git >/dev/null 2>&1; then
    log "Installation de Git requise pour récupérer les projets"
    set_progress "Préparation Git — actualisation des catalogues Ubuntu"
    update_apt_indexes
    set_progress "Préparation Git — installation de Git et des certificats"
    install_apt_packages git ca-certificates
    clear_progress
  fi

  activate_source_paths git
  mkdir -p "$ORMT_WSL_WORKSPACE"
  log "Mise à jour rapide des projets dans le système de fichiers WSL"
  if [[ "$ORMT_INFRA_REPO_URL$ORMT_API_REPO_URL$ORMT_WEB_REPO_URL" == *github.com* ]]; then
    printf '\nSi GitHub demande des identifiants pour un dépôt privé :\n'
    printf '  Username : ton nom utilisateur GitHub\n'
    printf '  Password : ton jeton GitHub, saisi de manière masquée\n'
    printf 'Le jeton est conservé uniquement en mémoire pendant 15 minutes.\n'
  fi
  if test "${ORMT_SELECT_GIT_BRANCHES:-false}" = "true"; then
    if test "$scope" = "infrastructure" || test "$scope" = "all"; then
      infra_branch="$(select_git_branch \
        "$ORMT_INFRA_REPO_URL" "$infra_branch" "Infrastructure")"
    fi
    if test "$scope" = "stage" || test "$scope" = "all"; then
      api_branch="$(select_git_branch \
        "$ORMT_API_REPO_URL" "$api_branch" "API")"
      web_branch="$(select_git_branch \
        "$ORMT_WEB_REPO_URL" "$web_branch" "Frontend")"
    fi
  fi
  if test "$scope" = "infrastructure" || test "$scope" = "all"; then
    sync_git_project "$ORMT_INFRA_DIR" \
      "$ORMT_INFRA_REPO_URL" "$infra_branch" "Infrastructure"
  fi
  if test "$scope" = "stage" || test "$scope" = "all"; then
    sync_git_project "$ORMT_API_DIR" \
      "$ORMT_API_REPO_URL" "$api_branch" "API"
    sync_git_project "$ORMT_WEB_DIR" \
      "$ORMT_WEB_REPO_URL" "$web_branch" "Frontend"
  fi
  mark_state source-mode git
  mark_state source-origin git
}

resolve_source_mode() {
  local requested="${1,,}"
  local provided_root="$2"
  local scope="$3"

  case "$requested" in
    provided)
      validate_source_tree "$provided_root" "$scope" ||
        die "Le mode Provided est incomplet pour le périmètre $scope dans: $provided_root"
      printf 'provided\n'
      ;;
    git)
      printf 'git\n'
      ;;
    auto)
      if validate_source_tree "$provided_root" "$scope" >/dev/null 2>&1; then
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
  local scope="$3"
  local selected
  selected="$(resolve_source_mode "$requested" "$provided_root" "$scope")"
  log "Provenance des projets sélectionnée: $selected (périmètre: $scope)"

  case "$selected" in
    provided)
      sync_provided_sources "$provided_root" "$scope"
      if test "$scope" = "stage" || test "$scope" = "all"; then
        normalize_build_wrappers
      fi
      ;;
    git) sync_git_sources "$scope" ;;
  esac
}
