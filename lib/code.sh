#!/usr/bin/env bash
#
# cam - Claude Code specific behavior.
# Code activation uses ~/.claude as a symlink.

# ---------------------------------------------------------------------------
# Claude Code process management (mockable for tests).
#
# These helpers mirror the Desktop process-control helpers in lib/desktop.sh.
# Everything is overridable via CAM_MOCK_CODE_* env vars so the test suite can
# simulate running / not-running / stop / force-stop cycles without touching a
# real Claude Code process.
# ---------------------------------------------------------------------------

# Is Claude Code currently running? Mockable via CAM_MOCK_CODE_RUNNING.
code_is_running() {
  if [[ -n "${CAM_MOCK_CODE_RUNNING:-}" ]]; then
    [[ "${CAM_MOCK_CODE_RUNNING}" == "1" ]]
    return
  fi
  # Match the executable name (not full path) to reduce false positives.
  pgrep -x claude >/dev/null 2>&1
}

# List running Claude Code PIDs. Mockable via CAM_MOCK_CODE_PIDS.
code_list_pids() {
  if [[ -n "${CAM_MOCK_CODE_PIDS:-}" ]]; then
    printf '%s' "$CAM_MOCK_CODE_PIDS"
    return
  fi
  pgrep -x claude 2>/dev/null
}

# Gracefully terminate Claude Code (SIGTERM). Mockable via CAM_MOCK_CODE_*:
#   CAM_MOCK_CODE_FORCE_REQUIRED=1 -> SIGTERM "fails" (process stays running)
#   otherwise                       -> process is marked as exited
code_stop() {
  if [[ -n "${CAM_MOCK_CODE_RUNNING:-}" || -n "${CAM_MOCK_CODE_PIDS:-}" ]]; then
    if [[ "${CAM_MOCK_CODE_FORCE_REQUIRED:-}" == "1" ]]; then
      return 0   # SIGTERM sent but process still running (caller must force)
    fi
    CAM_MOCK_CODE_RUNNING=0
    unset CAM_MOCK_CODE_PIDS
    return 0
  fi
  local pids
  pids="$(pgrep -x claude 2>/dev/null)"
  [[ -z "$pids" ]] && return 0
  # shellcheck disable=SC2086
  kill -TERM $pids 2>/dev/null
}

# Forcefully terminate Claude Code (SIGKILL). Mockable via CAM_MOCK_CODE_*.
code_stop_force() {
  if [[ -n "${CAM_MOCK_CODE_RUNNING:-}" || -n "${CAM_MOCK_CODE_PIDS:-}" ]]; then
    CAM_MOCK_CODE_RUNNING=0
    unset CAM_MOCK_CODE_PIDS
    return 0
  fi
  local pids
  pids="$(pgrep -x claude 2>/dev/null)"
  [[ -z "$pids" ]] && return 0
  # shellcheck disable=SC2086
  kill -KILL $pids 2>/dev/null
}

# Block until Claude Code is no longer running, or a safety timeout elapses.
# Returns 0 if it exited, 1 if it was still present after the timeout.
code_wait_for_exit() {
  wait_for_process_exit 'code_is_running' 10
}

# If Claude Code is running, gracefully terminate it (SIGTERM), wait for exit,
# then run the given switch command. If processes linger, offer a force
# (SIGKILL) option. Claude Code is never auto-relaunched: after switching, the
# user starts a fresh session against the new account. On decline, do nothing.
#
#   $1 = account name (for messages)
#   $2 = switch command to run after processes exit (e.g. a function/closure)
#
# Returns: 0 = switched (or not running), 1 = user declined / cancelled,
#          2 = headless + running (blocked).
code_restart_for_activation() {
  local name="$1" switch_cmd="$2"
  if ! code_is_running; then
    eval "$switch_cmd" || { err "Failed to switch the Code account."; return 1; }
    echo "Switched Claude Code account to \"$name\"."
    echo "Start a new Claude Code session to use the selected account."
    return 0
  fi
  local pids
  pids="$(code_list_pids)"
  vlog "Detected Claude Code processes:"
  local p
  for p in $pids; do vlog "  PID $p"; done
  if [[ "$HEADLESS" == "1" ]]; then
    err "Claude Code appears to be running. Close all Claude Code sessions and retry the switch."
    return 2
  fi
  echo "Claude Code appears to be running."
  if ! prompt "Close all Claude Code sessions before switching accounts? [Y/n] "; then
    err "Operation cancelled by user."
    return 1
  fi
  if [[ ! "$REPLY" =~ ^[Yy] ]]; then
    err "Operation cancelled by user."
    return 1
  fi
  vlog "Sending SIGTERM to Claude Code processes..."
  code_stop || { err "Failed to send SIGTERM to Claude Code."; return 1; }
  if ! code_wait_for_exit; then
    echo "Some Claude Code processes did not exit cleanly."
    if ! prompt "Force terminate them? [y/N] "; then
      err "Operation cancelled by user."
      return 1
    fi
    if [[ ! "$REPLY" =~ ^[Yy] ]]; then
      err "Operation cancelled by user."
      return 1
    fi
    vlog "Sending SIGKILL to Claude Code processes..."
    code_stop_force || { err "Failed to force-terminate Claude Code."; return 1; }
    code_wait_for_exit || { err "Claude Code did not exit even after SIGKILL. Aborting switch."; return 1; }
  fi
  vlog "All Claude Code processes exited."
  eval "$switch_cmd" || { err "Failed to switch the Code account."; return 1; }
  echo "Switched Claude Code account to \"$name\"."
  echo "Start a new Claude Code session to use the selected account."
  return 0
}

code_status() {
  local cur
  cur="$(get_current_code)"
  echo "Claude Code:"
  if [[ -n "$cur" ]]; then
    echo "  Active account: $cur"
    echo "  target: $(code_account_dir "$cur")"
  else
    echo "  Active account: (none)"
    if [[ -e "$ACTIVE_CODE" && ! -L "$ACTIVE_CODE" ]]; then
      echo "  Note: a real (non-symlink) $ACTIVE_CODE was found."
      echo "        This is a legacy installation. Run 'cam migrate'."
    fi
  fi
}

code_list()    { platform_list code "Claude Code Accounts:"; }
code_add()     { do_add "$1" code; }
code_activate() { do_activate_platform "$1" code; }
code_rename()  { do_rename "$1" "$2"; }
code_remove()  { do_remove "$1" code; }
