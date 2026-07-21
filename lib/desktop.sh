#!/usr/bin/env bash
#
# cam - Claude Desktop specific behavior.
# Desktop activation uses ~/Library/Application Support/Claude as a symlink.

# ---------------------------------------------------------------------------
# Desktop process management (mockable for tests).
#
# These helpers centralize all Claude Desktop process control so the AppleScript
# logic lives in exactly one place. Everything is overridable via env vars so
# the test suite can simulate a running / not-running / quit / launch cycle
# without touching a real Claude Desktop.
# ---------------------------------------------------------------------------

# Is Claude Desktop currently running? Mockable via CLAUDE_PROFILE_MOCK_RUNNING.
desktop_is_running() {
  if [[ -n "${CLAUDE_PROFILE_MOCK_RUNNING:-}" ]]; then
    [[ "${CLAUDE_PROFILE_MOCK_RUNNING}" == "1" ]]
    return
  fi
  local r
  r="$(osascript -e 'application "Claude" is running' 2>/dev/null || echo "false")"
  [[ "$r" == "true" ]]
}

# Gracefully quit Claude Desktop. Mockable via CLAUDE_PROFILE_MOCK_QUIT / the
# running mock: when running is mocked, a quit flips the running state off so
# wait-for-exit logic resolves immediately (simulating the app having quit).
desktop_quit() {
  if [[ "${CLAUDE_PROFILE_MOCK_QUIT:-}" == "1" || "${CLAUDE_PROFILE_MOCK_RUNNING:-}" == "1" ]]; then
    CLAUDE_PROFILE_MOCK_RUNNING=0
    return 0
  fi
  osascript -e 'tell application "Claude" to quit' 2>/dev/null
}

# Block until Claude Desktop is no longer running, or a safety timeout elapses.
# Returns 0 if it exited, 1 if it was still running after the timeout.
desktop_wait_for_exit() {
  wait_for_process_exit 'desktop_is_running' 30
}

# Launch Claude Desktop. Skipped when CLAUDE_PROFILE_DISABLE_OPEN=1 (tests) or
# when --no-launch was given. Mockable via CLAUDE_PROFILE_MOCK_LAUNCH.
desktop_launch() {
  if [[ "${CLAUDE_PROFILE_DISABLE_OPEN:-}" == "1" ]]; then
    return 0
  fi
  if [[ "${LAUNCH:-1}" != "1" ]]; then
    return 0
  fi
  if [[ -n "${CLAUDE_PROFILE_MOCK_LAUNCH:-}" ]]; then
    [[ "${CLAUDE_PROFILE_MOCK_LAUNCH}" == "1" ]]
    return
  fi
  open -a Claude
}

# If Claude Desktop is running, prompt the user to quit it, switch accounts, and
# reopen it. On acceptance: quit, wait for exit, run the given switch command,
# then relaunch. On decline: do nothing and report the cancellation.
#
#   $1 = account name (for the prompt)
#   $2 = switch command to run after Claude exits (e.g. a function/closure)
#
# Returns: 0 = switched (or not running), 1 = user declined / cancelled.
desktop_restart_for_activation() {
  local name="$1" switch_cmd="$2"
  if ! desktop_is_running; then
    eval "$switch_cmd" || { err "Failed to switch the Desktop account."; return 1; }
    desktop_launch
    return 0
  fi
  if [[ "$HEADLESS" == "1" ]]; then
    err "Claude Desktop is running. Quit Claude Desktop and retry the switch."
    return 2
  fi
  echo "Claude Desktop is currently running."
  if ! prompt "Close Claude Desktop, switch accounts, and reopen it with the new account? [Y/n] "; then
    err "Operation cancelled by user."
    return 1
  fi
  if [[ ! "$REPLY" =~ ^[Yy] ]]; then
    err "Operation cancelled by user."
    return 1
  fi
  desktop_quit || { err "Failed to quit Claude Desktop."; return 1; }
  if ! desktop_wait_for_exit; then
    err "Claude Desktop did not exit in time. Aborting switch."
    return 1
  fi
  eval "$switch_cmd" || { err "Failed to switch the Desktop account."; return 1; }
  # The user explicitly approved closing Claude, so always reopen it afterwards
  # regardless of --launch.
  LAUNCH=1 desktop_launch
  echo "Switched Desktop account to \"$name\" and reopened Claude Desktop."
  return 0
}

# Shared listing helper used by both `desktop list` and `code list`.
#   $1 = "desktop" | "code"   (which sub-directory to inspect)
#   $2 = header line to print
platform_list() {
  local kind="$1" title="$2"
  echo "$title"
  local names
  names="$(account_names)"
  local any=0 n dir st maxn=4
  local -a RNAME RLOG
  for n in $names; do
    [[ -z "$n" ]] && continue
    if [[ "$kind" == "desktop" ]]; then
      dir="$(desktop_account_dir "$n")"
    else
      dir="$(code_account_dir "$n")"
    fi
    [[ -d "$dir" ]] || continue
    any=1
    if [[ "$kind" == "desktop" ]]; then
      st="$(login_short "$(desktop_login_status "$dir")")"
    else
      st="$(login_short "$(code_login_status "$dir")")"
    fi
    RNAME+=("$n"); RLOG+=("$st")
    (( ${#n} > maxn )) && maxn=${#n}
  done
  if [[ "$any" -eq 0 ]]; then
    echo "  (none)"
    return
  fi
  printf '%-*s  %s\n' "$maxn" "NAME" "LOGGED"
  local i
  for i in "${!RNAME[@]}"; do
    printf '%-*s  %s\n' "$maxn" "${RNAME[$i]}" "${RLOG[$i]}"
  done
}

desktop_status() {
  local cur
  cur="$(get_current_desktop)"
  echo "Claude Desktop:"
  if [[ -n "$cur" ]]; then
    echo "  Active account: $cur"
    echo "  target: $(desktop_account_dir "$cur")"
  else
    echo "  Active account: (none)"
    if [[ -e "$ACTIVE_DESKTOP" && ! -L "$ACTIVE_DESKTOP" ]]; then
      echo "  Note: a real (non-symlink) $ACTIVE_DESKTOP was found."
      echo "        A real (non-symlink) directory exists at this path. cam will not overwrite it."
    fi
  fi
}

desktop_list()    { platform_list desktop "Claude Desktop Accounts:"; }
desktop_add()     { do_add "$1" desktop; }
desktop_activate() { do_activate_platform "$1" desktop; }
desktop_rename()  { do_rename "$1" "$2"; }
desktop_remove()  { do_remove "$1" desktop; }
