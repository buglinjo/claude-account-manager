#!/usr/bin/env bash
#
# cam - CLI command implementations and routing.
#
# This module owns the shared command implementations (do_*), the combined
# status/list views, the per-product subcommand dispatchers, help, and main().

# ---------------------------------------------------------------------------
# Shared command implementations
# ---------------------------------------------------------------------------

# Create an isolated account directory (optionally just one platform).
#   $1 = name
#   $2 = platform: "" | desktop | code
#
# Accounts are SPARSE: a bare `cam add <name>` creates only the (empty) account
# directory. Component sub-directories (desktop/, code/) are created only when
# the user explicitly enables that platform via `desktop add` / `code add`.
# We never create an empty component directory automatically, and the only
# canonical code storage is accounts/<name>/code (never a root-level code/).
do_add() {
  local name="$1" platform="${2:-}"
  validate_account_name "$name"
  local existed=0
  account_exists "$name" && existed=1
  if [[ "$platform" == "desktop" ]]; then
    mkdir -p -- "$(desktop_account_dir "$name")"
  elif [[ "$platform" == "code" ]]; then
    mkdir -p -- "$(code_account_dir "$name")"
  else
    mkdir -p -- "$(account_dir "$name")"
  fi
  if [[ "$existed" -eq 0 ]]; then
    config_add_account "$name"
  fi
  if [[ "$platform" == "desktop" ]]; then
    echo "Created Claude Desktop account: $name"
  elif [[ "$platform" == "code" ]]; then
    echo "Created Claude Code account: $name"
  elif [[ "$existed" -eq 0 ]]; then
    echo "Created account \"$name\"."
    echo "Add a platform with: cam desktop add $name   (or: cam code add $name)"
  else
    echo "Account \"$name\" already exists."
  fi
}

# Activate a account on a single platform (strict: account subdir must exist).
#   $1 = name
#   $2 = platform: desktop | code
do_activate_platform() {
  local name="$1" platform="$2"
  validate_account_name "$name"
  local pdir rc
  if [[ "$platform" == "desktop" ]]; then
    pdir="$(desktop_account_dir "$name")"
    [[ -d "$pdir" ]] || { err "Claude Desktop account \"$name\" does not exist."; exit 2; }
    if ! is_desktop_available; then
      # Desktop not installed: just repoint (skip the running/relaunch dance).
      rc=0; activate_desktop_account "$name" || rc=$?
      [[ "$rc" -eq 2 ]] && exit 5
      return 0
    else
      # If Claude Desktop is running, prompt to quit/switch/relaunch, or block.
      rc=0; desktop_restart_for_activation "$name" "activate_desktop_account \"$name\"" || rc=$?
      if [[ "$rc" -eq 2 ]]; then exit 7; fi
      if [[ "$rc" -ne 0 ]]; then exit 6; fi
    fi
  else
    pdir="$(code_account_dir "$name")"
    [[ -d "$pdir" ]] || { err "Claude Code account \"$name\" does not exist."; exit 2; }
    if ! is_code_available; then
      # Code not installed: just repoint (skip the running/stop dance).
      rc=0; activate_code_account "$name" || rc=$?
      [[ "$rc" -eq 2 ]] && exit 5
      return 0
    else
      # If Claude Code is running, prompt to terminate it before switching.
      rc=0; code_restart_for_activation "$name" "activate_code_account \"$name\"" || rc=$?
      if [[ "$rc" -eq 2 ]]; then exit 7; fi
      if [[ "$rc" -ne 0 ]]; then exit 6; fi
    fi
  fi
}

# Activate a account across all available platforms (combined). Missing
# platform subdirs, or a missing product, produce warnings only; the command
# succeeds if at least one platform was activated (or would be, were the
# product installed and the account has the relevant subdir).
do_activate_combined() {
  local name="$1"
  validate_account_name "$name"
  account_exists "$name" || { err "Account \"$name\" does not exist."; exit 2; }

  local activated=0 parts="" has_any=0 rc
  if desktop_account_exists "$name"; then
    has_any=1
    if ! is_desktop_available; then
      echo "Warning: Claude Desktop is not installed. Skipping Desktop activation."
    else
      rc=0; desktop_restart_for_activation "$name" "activate_desktop_account \"$name\"" || rc=$?
      if [[ "$rc" -eq 0 ]]; then activated=1; parts="Desktop";
      elif [[ "$rc" -eq 1 ]]; then exit 6;        # user declined / switch failed
      elif [[ "$rc" -eq 2 ]]; then exit 7; fi     # headless + running
    fi
  else
    echo "Warning: Account \"$name\" does not have a Claude Desktop account. Skipping Desktop."
  fi
  if code_account_exists "$name"; then
    has_any=1
    if ! is_code_available; then
      echo "Warning: Claude Code is not installed. Skipping Code activation."
    else
      rc=0; code_restart_for_activation "$name" "activate_code_account \"$name\"" || rc=$?
      if [[ "$rc" -eq 0 ]]; then activated=1; parts="${parts:+$parts, }Code";
      elif [[ "$rc" -eq 1 ]]; then exit 6;        # user declined / switch failed
      elif [[ "$rc" -eq 2 ]]; then exit 7; fi     # headless + running
    fi
  else
    echo "Warning: Account \"$name\" does not have a Claude Code account. Skipping Code."
  fi

  if [[ "$activated" -eq 0 ]]; then
    if [[ "$has_any" -eq 1 ]]; then
      # Account has data but the required Claude product(s) are not installed.
      echo "Warning: nothing was activated because the required Claude product(s) are not installed."
      exit 0
    fi
    err "Account \"$name\" has neither a Desktop nor a Code account."
    exit 2
  fi
  echo "Activated account: $name ($parts)"
}

do_rename() {
  local old="$1" new="$2"
  validate_account_name "$old"
  validate_account_name "$new"
  account_exists "$old" || { err "Account \"$old\" does not exist."; exit 2; }
  account_exists "$new" && { err "Account \"$new\" already exists."; exit 1; }

  local dcur ccur
  dcur="$(get_current_desktop)"; ccur="$(get_current_code)"

  mv -- "$(account_dir "$old")" "$(account_dir "$new")" || { err "Failed to rename account."; exit 5; }
  config_rename_account "$old" "$new"

  if [[ "$dcur" == "$old" ]]; then
    make_symlink "$(desktop_account_dir "$new")" "$ACTIVE_DESKTOP" || exit 5
  fi
  if [[ "$ccur" == "$old" ]]; then
    make_symlink "$(code_account_dir "$new")" "$ACTIVE_CODE" || exit 5
  fi
  echo "Renamed account \"$old\" to \"$new\"."
}

# Remove a account (entire directory). `platform` scope: "" | desktop | code.
do_remove() {
  local name="$1" platform="${2:-}"
  validate_account_name "$name"

  if [[ "$platform" == "desktop" ]]; then
    desktop_account_exists "$name" || { err "Claude Desktop account \"$name\" does not exist."; exit 2; }
  elif [[ "$platform" == "code" ]]; then
    code_account_exists "$name" || { err "Claude Code account \"$name\" does not exist."; exit 2; }
  else
    account_exists "$name" || { err "Account \"$name\" does not exist."; exit 2; }
  fi

  # Active checks (platform-aware).
  local active=0
  if [[ "$platform" == "desktop" ]]; then
    [[ "$(get_current_desktop)" == "$name" ]] && active=1
  elif [[ "$platform" == "code" ]]; then
    [[ "$(get_current_code)" == "$name" ]] && active=1
  else
    [[ "$(get_current_desktop)" == "$name" || "$(get_current_code)" == "$name" ]] && active=1
  fi

  # Safety: never auto-delete in headless mode without --force.
  if [[ "$FORCE" != "1" && "$HEADLESS" == "1" ]]; then
    err "Refusing to remove account in headless mode without --force."
    exit 1
  fi

  if [[ "$active" -eq 1 && "$FORCE" != "1" ]]; then
    err "Cannot remove the active account \"$name\". Activate another account first, or use --force."
    exit 3
  fi

  if [[ "$FORCE" != "1" ]]; then
    if prompt "Remove account \"$name\"? This permanently deletes its data. (y/n) "; then
      if [[ ! "$REPLY" =~ ^[Yy] ]]; then
        err "Operation cancelled by user."
        exit 6
      fi
    else
      err "Operation cancelled by user."
      exit 6
    fi
  fi

  if [[ "$platform" == "desktop" ]]; then
    if [[ "$(get_current_desktop)" == "$name" ]]; then
      rm -f -- "$ACTIVE_DESKTOP"   # drop dangling symlink
    fi
    rm -rf -- "$(desktop_account_dir "$name")" || { err "Failed to remove account."; exit 5; }
    echo "Removed Claude Desktop account \"$name\"."
  elif [[ "$platform" == "code" ]]; then
    if [[ "$(get_current_code)" == "$name" ]]; then
      rm -f -- "$ACTIVE_CODE"   # drop dangling symlink
    fi
    rm -rf -- "$(code_account_dir "$name")" || { err "Failed to remove account."; exit 5; }
    echo "Removed Claude Code account \"$name\"."
  else
    rm -rf -- "$(account_dir "$name")" || { err "Failed to remove account."; exit 5; }
    config_remove_account "$name"
    echo "Removed account \"$name\"."
  fi
}

# ---------------------------------------------------------------------------
# Combined status / list
# ---------------------------------------------------------------------------

combined_status() {
  local dcur ccur
  dcur="$(get_current_desktop)"; ccur="$(get_current_code)"
  if [[ -n "$dcur" && "$dcur" == "$ccur" ]]; then
    echo "Active account:"
    echo "  $dcur"
  else
    echo "Active account:"
    echo "  Desktop: ${dcur:-none}"
    echo "  Code:    ${ccur:-none}"
  fi
  echo
  desktop_status
  echo
  code_status
}

combined_list() {
  echo "NAME      DESKTOP    CODE"
  local names
  names="$(account_names)"
  [[ -z "$names" ]] && { echo "  (none)"; return; }
  local n maxn=4 dt ct
  for n in $names; do (( ${#n} > maxn )) && maxn=${#n}; done
  for n in $names; do
    [[ -z "$n" ]] && continue
    dt="no"; desktop_account_exists "$n" && dt="yes"
    ct="no"; code_account_exists "$n" && ct="yes"
    printf '%-*s  %-9s  %s\n' "$maxn" "$n" "$dt" "$ct"
  done
}

# ---------------------------------------------------------------------------
# Subcommand dispatchers
# ---------------------------------------------------------------------------

desktop_main() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    status)  desktop_status ;;
    list)    desktop_list ;;
    add)
      [[ -z "${1:-}" ]] && { err "Usage: cam desktop add <name>"; exit 1; }
      desktop_add "${1}" ;;
    activate)
      [[ -z "${1:-}" ]] && { err "Usage: cam desktop activate <name>"; exit 1; }
      desktop_activate "${1}" ;;
    rename)
      [[ -z "${1:-}" || -z "${2:-}" ]] && { err "Usage: cam desktop rename <old> <new>"; exit 1; }
      desktop_rename "${1}" "${2}" ;;
    remove)
      [[ -z "${1:-}" ]] && { err "Usage: cam desktop remove <name>"; exit 1; }
      desktop_remove "${1}" ;;
    "")      err "Usage: cam desktop <status|list|add|activate|rename|remove>"; exit 1 ;;
    *)       err "Unknown desktop command: $sub"; exit 1 ;;
  esac
}

code_main() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    status)  code_status ;;
    list)    code_list ;;
    add)
      [[ -z "${1:-}" ]] && { err "Usage: cam code add <name>"; exit 1; }
      code_add "${1}" ;;
    activate)
      [[ -z "${1:-}" ]] && { err "Usage: cam code activate <name>"; exit 1; }
      code_activate "${1}" ;;
    rename)
      [[ -z "${1:-}" || -z "${2:-}" ]] && { err "Usage: cam code rename <old> <new>"; exit 1; }
      code_rename "${1}" "${2}" ;;
    remove)
      [[ -z "${1:-}" ]] && { err "Usage: cam code remove <name>"; exit 1; }
      code_remove "${1}" ;;
    "")      err "Usage: cam code <status|list|add|activate|rename|remove>"; exit 1 ;;
    *)       err "Unknown code command: $sub"; exit 1 ;;
  esac
}

combined_main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    status)  combined_status ;;
    list)    combined_list ;;
    add)
      [[ -z "${1:-}" ]] && { err "Usage: cam add <name>"; exit 1; }
      do_add "${1}" ;;
    activate)
      [[ -z "${1:-}" ]] && { err "Usage: cam activate <name>"; exit 1; }
      do_activate_combined "${1}" ;;
    rename)
      [[ -z "${1:-}" || -z "${2:-}" ]] && { err "Usage: cam rename <old> <new>"; exit 1; }
      do_rename "${1}" "${2}" ;;
    remove)
      [[ -z "${1:-}" ]] && { err "Usage: cam remove <name>"; exit 1; }
      do_remove "${1}" ;;
    "")      err "Usage: cam <status|list|activate|add|rename|remove>"; print_help; exit 1 ;;
    *)       err "Unknown command: $cmd"; print_help; exit 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

print_help() {
  cat <<'EOF'
cam - manage multiple Claude accounts (Desktop + Code) via symlinked accounts.

cam owns its data under a single canonical home:

  ~/.claude-account-manager/
    config.json          # account names + display names (no active state)
    accounts/
      work/
        desktop/        # Claude Desktop data
        code/           # Claude Code data
    personal/
      desktop/
      code/

The ACTIVE account is a SYMLINK (the symlink is the source of truth):

  ~/Library/Application Support/Claude  ->  .../accounts/work/desktop
  ~/.claude                             ->  .../accounts/work/code

Switching never moves or copies data - it only updates the symlinks.

USAGE:
  cam <command> [args] [flags]              # both Desktop + Code
  cam desktop <command> [args] [flags]      # Desktop only
  cam code <command> [args] [flags]         # Code only

COMBINED COMMANDS (cam ...):
  status              Show active account + current symlink targets.
  list                List all accounts with DESKTOP / CODE presence.
  add <name>          Create a (sparse) account; add desktop/code with the
                      scoped commands below.
  activate <name>     Activate available platforms for the account. Missing
                       platform accounts print a warning and are skipped.
  rename <old> <new>  Rename a account directory (updates symlinks + config).
  remove <name>       Remove a account (confirmation; --force bypasses).

DESKTOP COMMANDS (cam desktop ...):
  status              Show the active Desktop symlink target.
  list                List Desktop accounts (login state).
  add <name>          Create a Desktop account directory only.
  activate <name>     Point ~/Library/Application Support/Claude at the account.
                       If Claude Desktop is running, you are prompted to quit it,
                       switch, and reopen it with the new account.
  rename <old> <new>  Rename a account (strict: Desktop account must exist).
  remove <name>       Remove a account (strict; confirmation).

CODE COMMANDS (cam code ...):
  status              Show the active Code symlink target (~/.claude).
  list                List Code accounts (login state).
  add <name>          Create a Code account directory only.
   activate <name>     Point ~/.claude at the account. If Claude Code is running,
                       you are prompted to terminate it before switching (it is
                       never auto-relaunched).
  rename <old> <new>  Rename a account (strict: Code account must exist).
  remove <name>       Remove a account (strict; confirmation).

NOTES:
  cam works even when Claude Desktop or Claude Code is absent. If a product is
  not installed, activation of that product is skipped with a warning. The
  active account is a symlink (~/.claude and Application Support/Claude); no
  environment variables or shell changes are required.

FLAGS:
  --headless          Never prompt; report errors via exit codes.
  --force             Bypass confirmation prompts (e.g. remove).
  --launch            Reopen Claude Desktop after switching (default).
  --no-launch         Do not reopen Claude Desktop after switching.
  --verbose           Show detailed operations.
  --help, -h          Show this help.

EXIT CODES:
  0  Success
  1  Invalid arguments
  2  Account does not exist
  3  Invalid account state (e.g. removing the active account)
  4  (reserved)
  5  File/symlink operation failed
  6  User cancelled
  7  Claude Desktop is running (headless switch blocked)
EOF
}

main() {
  local args=()
  local a
  for a in "$@"; do
    case "$a" in
      --headless)   HEADLESS=1 ;;
      --force)      FORCE=1 ;;
      --verbose)    VERBOSE=1 ;;
      --launch)     LAUNCH=1 ;;
      --no-launch)  LAUNCH=0 ;;
      --help|-h)    print_help; exit 0 ;;
      *)            args+=("$a") ;;
    esac
  done

  local cmd="${args[0]:-}"
  case "$cmd" in
    desktop)
      desktop_main "${args[@]:1}" ;;
    code)
      code_main "${args[@]:1}" ;;
    status|list|activate|add|rename|remove)
      combined_main "$cmd" "${args[@]:1}" ;;
    "")      err "No command specified."; print_help; exit 1 ;;
    *)       err "Unknown command: $cmd"; print_help; exit 1 ;;
  esac
}
