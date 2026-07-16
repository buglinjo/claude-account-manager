#!/usr/bin/env bash
#
# cam - migration subsystem.
#
# Two sources of legacy data are handled:
#
#  (A) The previous storage location ~/.config/claude-account-manager must be
#      moved into the new canonical home ~/.claude-account-manager.
#  (B) Pre-symlink Claude layouts:
#        ~/Library/Application Support/Claude          (active, real dir)
#        ~/Library/Application Support/Claude-<name>   (inactive, real dir)
#        a real ~/.claude directory
#        the old $OLD_CONFIG_HOME/code/<name> layout
#      are moved into accounts/<name>/{desktop,code}.
#
# Never overwrites existing new data; requires confirmation (or --force).

# Move the previous storage location into the new canonical home, once.
migrate_old_location() {
  [[ -e "$OLD_CONFIG_HOME" ]] || return 0
  if [[ -e "$CAM_HOME" ]]; then
    err "Both the old cam location ($OLD_CONFIG_HOME) and the new one ($CAM_HOME) exist."
    err "Remove or rename one before migrating, or move the data manually."
    exit 1
  fi
  if [[ "$FORCE" != "1" ]]; then
    if [[ "$HEADLESS" == "1" ]]; then
      err "Refusing to migrate old data in headless mode without --force."
      exit 1
    fi
    if ! prompt "Found old cam data at $OLD_CONFIG_HOME. Move it to $CAM_HOME? (y/n) "; then
      err "Migration cancelled."
      exit 6
    fi
  fi
  mkdir -p -- "$(dirname "$CAM_HOME")"
  mv -- "$OLD_CONFIG_HOME" "$CAM_HOME" || { err "Failed to move old cam data."; exit 5; }
  # Rename the legacy inner profiles/ directory to the new accounts/ layout.
  if [[ -d "$CAM_HOME/profiles" && ! -e "$CAM_HOME/accounts" ]]; then
    mv -- "$CAM_HOME/profiles" "$CAM_HOME/accounts" || { err "Failed to rename profiles directory."; exit 5; }
  fi
  echo "Moved old cam data: $OLD_CONFIG_HOME -> $CAM_HOME"
  MIGRATE_OLD_MOVED=1
}

cmd_migrate() {
  local active_name="${1:-}"
  local MIGRATE_OLD_MOVED=0

  # (A) One-time relocation of the previous storage directory.
  migrate_old_location

  local -a legacy; legacy=()
  shopt -s nullglob
  local d n
  for d in "$BASE_DIR"/Claude-*/; do
    n="$(basename "$d")"; n="${n#Claude-}"
    [[ -n "$n" ]] && legacy+=("$n")
  done
  shopt -u nullglob

  local has_active=0 has_code_real=0 has_old_code=0
  [[ -d "$ACTIVE_DESKTOP" && ! -L "$ACTIVE_DESKTOP" ]] && has_active=1
  [[ -d "$ACTIVE_CODE" && ! -L "$ACTIVE_CODE" ]] && has_code_real=1
  # Legacy Code layout lives under the OLD location only
  # ($OLD_CONFIG_HOME/code/<name>); the canonical location is now
  # accounts/<name>/code, so there is never a root-level $CAM_HOME/code.
  for src in "$OLD_CONFIG_HOME/code"; do
    if [[ -d "$src" && -n "$(ls -A "$src" 2>/dev/null)" ]]; then
      has_old_code=1
      break
    fi
  done

  if [[ "$has_active" -eq 0 && "${#legacy[@]}" -eq 0 && "$has_code_real" -eq 0 && "$has_old_code" -eq 0 ]]; then
    if [[ "$MIGRATE_OLD_MOVED" -eq 1 ]]; then
      echo "Migration complete. Run 'cam status' to verify."
      exit 0
    fi
    err "No legacy Claude data found to migrate."
    exit 1
  fi

  # The active Desktop directory and/or the real ~/.claude both become the same
  # account, so they share one name.
  if [[ -z "$active_name" && ( "$has_active" -eq 1 || "$has_code_real" -eq 1 ) ]]; then
    if [[ "$HEADLESS" == "1" ]]; then
      err "Specify the account name: cam migrate <name>"
      exit 1
    fi
    printf 'Name for the account to migrate into: ' >&2
    IFS= read -r active_name
    active_name="$(printf '%s' "$active_name" | tr -d '[:space:]')"
  fi
  [[ -n "$active_name" ]] && validate_account_name "$active_name"

  if [[ "$FORCE" != "1" ]]; then
    if [[ "$HEADLESS" == "1" ]]; then
      err "Refusing to migrate in headless mode without --force."
      exit 1
    fi
    if ! prompt "Migrate legacy Claude data into accounts? This moves your existing data (it is never copied). (y/n) "; then
      err "Migration cancelled."
      exit 6
    fi
  fi

  mkdir -p -- "$ACCOUNTS_DIR" || { err "Failed to create accounts directory."; exit 5; }

  # Legacy inactive accounts -> accounts/<name>/desktop
  if [[ "${#legacy[@]}" -gt 0 ]]; then
    local ln_
    for ln_ in "${legacy[@]}"; do
      if [[ -e "$ACCOUNTS_DIR/$ln_" ]]; then
        err "Account '$ln_' already exists; skipping legacy '$ln_'."
        continue
      fi
      mkdir -p -- "$ACCOUNTS_DIR/$ln_"
      mv -- "$BASE_DIR/Claude-$ln_" "$ACCOUNTS_DIR/$ln_/desktop" || { err "Failed to move legacy '$ln_'."; exit 5; }
      config_add_account "$ln_"
      echo "Migrated legacy account '$ln_' -> accounts/$ln_/desktop"
    done
  fi

  # Active Desktop account -> accounts/<active_name>/desktop + symlink
  if [[ "$has_active" -eq 1 ]]; then
    if [[ -z "$active_name" ]]; then
      err "Specify a name: cam migrate <name>"
      exit 1
    fi
    if [[ -e "$ACCOUNTS_DIR/$active_name" ]]; then
      err "Account '$active_name' already exists; cannot place active data there."
      exit 1
    fi
    mkdir -p -- "$ACCOUNTS_DIR/$active_name"
    mv -- "$ACTIVE_DESKTOP" "$ACCOUNTS_DIR/$active_name/desktop" || { err "Failed to move active account."; exit 5; }
    config_add_account "$active_name"
    make_symlink "$(desktop_account_dir "$active_name")" "$ACTIVE_DESKTOP" || exit 5
    echo "Migrated active Desktop account -> accounts/$active_name/desktop (now active)"
  elif [[ "${#legacy[@]}" -gt 0 ]]; then
    # No active dir existed; make the first legacy account active so the
    # system is in a usable state.
    local first="${legacy[0]}"
    make_symlink "$(desktop_account_dir "$first")" "$ACTIVE_DESKTOP" || exit 5
    echo "Set '$first' as the active Desktop account."
  fi

  # Real ~/.claude (pre-symlink Claude Code data) -> accounts/<active_name>/code
  if [[ "$has_code_real" -eq 1 ]]; then
    if [[ -z "$active_name" ]]; then
      err "Specify a name: cam migrate <name>"
      exit 1
    fi
    mkdir -p -- "$ACCOUNTS_DIR/$active_name"
    if [[ -e "$(code_account_dir "$active_name")" ]]; then
      err "Code account '$active_name' already exists; cannot place ~/.claude data there."
      exit 1
    fi
    mv -- "$ACTIVE_CODE" "$ACCOUNTS_DIR/$active_name/code" || { err "Failed to move ~/.claude."; exit 5; }
    config_add_account "$active_name"
    make_symlink "$(code_account_dir "$active_name")" "$ACTIVE_CODE" || exit 5
    echo "Migrated ~/.claude -> accounts/$active_name/code (now active)"
  fi

  # Old Code layout ($OLD_CONFIG_HOME/code/<name>) -> accounts/<name>/code.
  # (There is no longer a root-level $CAM_HOME/code directory.)
  if [[ "$has_old_code" -eq 1 ]]; then
    for src in "$OLD_CONFIG_HOME/code"; do
      [[ -d "$src" ]] || continue
      shopt -s nullglob
      local cd_
      for cd_ in "$src"/*/; do
        n="$(basename "$cd_")"
        if [[ -d "$ACCOUNTS_DIR/$n" && ! -e "$ACCOUNTS_DIR/$n/code" ]]; then
          mv -- "$cd_" "$ACCOUNTS_DIR/$n/code" && echo "Migrated Code account '$n' -> accounts/$n/code"
        fi
      done
      shopt -u nullglob
    done
  fi

  echo "Migration complete. Run 'cam status' to verify."
}
