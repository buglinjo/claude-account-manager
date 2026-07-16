#!/usr/bin/env bash
#
# cam - generic helpers shared across all modules.
# Contains NO Desktop/Code specific logic.

# Print an error to stderr.
err()  { printf '%s\n' "$*" >&2; }

# Print a warning to stderr (semantically distinct from a hard error).
warn() { printf '%s\n' "$*" >&2; }

# Print a verbose trace line to stderr (only when --verbose is set).
vlog() { if [[ "$VERBOSE" == "1" ]]; then printf '[verbose] %s\n' "$*" >&2; fi; }

# Prompt the user on stderr and read a line into REPLY.
# Returns 1 (and does not read) when running headless.
prompt() {
  if [[ "$HEADLESS" == "1" ]]; then
    return 1
  fi
  printf '%s' "$1" >&2
  IFS= read -r REPLY
  return 0
}

# Prompt and succeed only if the user answers yes (y/Y).
confirm() {
  if ! prompt "$1"; then
    return 1
  fi
  [[ "$REPLY" =~ ^[Yy] ]]
}

# Validate an account name. Exits 1 on invalid input.
validate_account_name() {
  local n="$1"
  if [[ -z "$n" ]]; then
    err "Account name cannot be empty."
    exit 1
  fi
  if [[ "$n" == "Claude" ]]; then
    err "Invalid account name \"$n\"."
    exit 1
  fi
  if [[ ! "$n" =~ ^[A-Za-z0-9_-]+$ ]]; then
    err "Invalid account name \"$n\". Use letters, digits, hyphen or underscore only."
    exit 1
  fi
}

# Poll a process-presence probe until it reports "gone", or a timeout elapses.
#   $1 = shell command to re-evaluate (returns 0 / true while still running)
#   $2 = max seconds to wait (default: 10)
# Returns 0 if the process exited, 1 if it was still present after the timeout.
# Sleeps 0.2s between probes. Callers that mock "running" should make their
# probe resolve in a single iteration so no real sleep is needed.
wait_for_process_exit() {
  local probe="$1" max="${2:-10}"
  local waited=0
  while eval "$probe"; do
    [[ "$waited" -ge "${max%.*}" ]] && return 1
    sleep 0.2
    waited=$((waited + 1))
  done
  return 0
}

# Map a login-status token to a short label.
login_short() {
  case "$1" in
    true)  echo "yes" ;;
    false) echo "no" ;;
    *)     echo "unknown" ;;
  esac
}
