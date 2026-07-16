#!/usr/bin/env bash
#
# cam - external detection (products, running state, login state).
# All checks are isolated and mockable for tests.

# --- Product availability -----------------------------------------------------
# A missing product means the corresponding activation is skipped, never fatal.

is_desktop_available() {
  if [[ -n "${CLAUDE_PROFILE_MOCK_DESKTOP:-}" ]]; then
    [[ "${CLAUDE_PROFILE_MOCK_DESKTOP}" == "1" ]]
    return
  fi
  # Claude Desktop stores data under Application Support and ships as Claude.app.
  [[ -d "/Applications/Claude.app" ]]
}

is_code_available() {
  if [[ -n "${CLAUDE_PROFILE_MOCK_CODE:-}" ]]; then
    [[ "${CLAUDE_PROFILE_MOCK_CODE}" == "1" ]]
    return
  fi
  command -v claude >/dev/null 2>&1
}

# --- Running detection --------------------------------------------------------

is_claude_desktop_running() {
  if [[ -n "${CLAUDE_PROFILE_MOCK_RUNNING:-}" ]]; then
    [[ "${CLAUDE_PROFILE_MOCK_RUNNING}" == "1" ]]
    return
  fi
  local r
  r="$(osascript -e 'application "Claude" is running' 2>/dev/null || echo "false")"
  [[ "$r" == "true" ]]
}

# --- Login detection ----------------------------------------------------------
# Returns only: true | false | unknown. Never exposes credentials.

desktop_login_status() {
  local path="$1"
  if [[ ! -d "$path" ]]; then
    echo "unknown"
    return
  fi
  local found=0
  if [[ -f "$path/Cookies" ]]; then
    local sz
    sz="$(stat -f%z "$path/Cookies" 2>/dev/null || echo 0)"
    if [[ "$sz" -gt 100 ]]; then found=1; fi
  fi
  if [[ -d "$path/Local Storage" ]]; then
    if find "$path/Local Storage" -type f 2>/dev/null | grep -q .; then found=1; fi
  fi
  if [[ -d "$path/IndexedDB" ]]; then
    if find "$path/IndexedDB" -type f 2>/dev/null | grep -q .; then found=1; fi
  fi
  if [[ "$found" -eq 1 ]]; then echo "true"; else echo "false"; fi
}

code_login_status() {
  local path="$1"
  [[ -d "$path" ]] || { echo "unknown"; return; }
  local found=0 f
  for f in "$path/.credentials.json" "$path/.claude.json" "$path/credentials.json" "$path/auth.json"; do
    [[ -f "$f" ]] && found=1
  done
  if [[ "$found" -eq 0 && -d "$path/projects" ]]; then
    if find "$path/projects" -type f 2>/dev/null | grep -q .; then found=1; fi
  fi
  if [[ "$found" -eq 1 ]]; then echo "true"; else echo "unknown"; fi
}
