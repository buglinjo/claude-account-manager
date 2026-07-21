#!/usr/bin/env bash
#
# cam - symlink operations.
#
# SYMLINKS ARE THE SOURCE OF TRUTH for which account is active. The active
# Claude Desktop directory and active ~/.claude directory are symlinks pointing
# into accounts/<name>/{desktop,code}. Switching never moves or copies data; it
# only updates the symlink with `ln -sfn`.
#
# Rules enforced here:
#   - Never overwrite a real (non-symlink) directory.
#   - Only replace symlinks.
#   - Never delete user data.

# Create a symlink `link` -> `target`. Target must exist and be a directory.
# Refuses to overwrite a real (non-symlink) directory.
make_symlink() {
  local target="$1" link="$2"
  if [[ ! -e "$target" ]]; then
    err "Target does not exist: $target"
    return 1
  fi
  if [[ ! -d "$target" ]]; then
    err "Target is not a directory: $target"
    return 1
  fi
  if [[ -e "$link" && ! -L "$link" ]]; then
    err "Path already exists and is a real directory (not a symlink): $link"
    err "A real (non-symlink) directory already exists at $link. cam will not overwrite it."
    return 1
  fi
  ln -sfn -- "$target" "$link" || { err "Failed to create symlink: $link"; return 1; }
  vlog "symlink $link -> $target"
  return 0
}

# Resolve which account a symlink points to (for desktop|code). Prints the
# account name, or empty if the link is absent / not a symlink / not a account.
resolve_account() {
  local link="$1" kind="$2"
  python3 - "$link" "$kind" "$ACCOUNTS_DIR" <<'PY'
import os, sys
link, kind, accounts = sys.argv[1], sys.argv[2], sys.argv[3]
if not os.path.islink(link):
    print(""); sys.exit(0)
try:
    tgt = os.path.realpath(link)
    base = os.path.realpath(accounts)
except Exception:
    print(""); sys.exit(0)
prefix = os.path.join(base, "")
if tgt.startswith(prefix):
    parts = tgt[len(prefix):].split(os.sep)
    if len(parts) >= 2 and parts[1] == kind:
        print(parts[0]); sys.exit(0)
print("")
PY
}

# Current active account name for each platform (empty if none).
get_current_desktop() { resolve_account "$ACTIVE_DESKTOP" desktop; }
get_current_code()    { resolve_account "$ACTIVE_CODE" code; }

# The symlink paths that represent the active Desktop / Code account.
desktop_active_target() { echo "$ACTIVE_DESKTOP"; }
code_active_target()    { echo "$ACTIVE_CODE"; }

# Activate a single platform's account by repointing its symlink.
# Returns: 0 = activated, 1 = skipped (product not installed), 2 = hard failure.
# The decision to relaunch Claude Desktop is owned by the caller (see
# desktop_restart_for_activation in lib/desktop.sh), so this function only
# repoints the symlink.
activate_desktop_account() {
  local name="$1"
  if ! is_desktop_available; then
    echo "Warning: Claude Desktop is not installed. Skipping Desktop activation."
    return 1
  fi
  make_symlink "$(desktop_account_dir "$name")" "$ACTIVE_DESKTOP" || return 2
  echo "Activated Claude Desktop account: $name"
  return 0
}

activate_code_account() {
  local name="$1"
  if ! is_code_available; then
    echo "Warning: Claude Code is not installed. Skipping Code activation."
    return 1
  fi
  make_symlink "$(code_account_dir "$name")" "$ACTIVE_CODE" || return 2
  echo "Activated Claude Code account: $name"
  return 0
}
