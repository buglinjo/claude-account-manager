#!/usr/bin/env bash
#
# Automated tests for cam (symlink-based profile architecture).
#
# Uses TEMPORARY fake Application Support + config + ~/.claude directories.
# NEVER touches the real ~/Library/Application Support/Claude or ~/.claude.
#
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/cam"

PASS=0
FAIL=0

# Captured results of the last run_out() call.
OUT=""      # stdout
ERR=""      # stderr
CODE=0      # exit code

# Run the script under test with a fake environment.
run_out() {
  MOCK="${MOCK:-0}"
  local DMOCK="${CAM_DESKTOP:-1}" CMOCK="${CAM_CODE:-1}"
  local stdin_arg=""
  if [[ -t 0 ]]; then stdin_arg="</dev/null"; fi
  OUT="$(CLAUDE_ACCOUNT_MANAGER_HOME="$CONF" \
         CLAUDE_PROFILE_OLD_CONFIG="$OLD_CONFIG" \
         CLAUDE_PROFILE_APP_SUPPORT="$BASE" \
         CLAUDE_PROFILE_CLUDE_HOME="$CLHOME" \
         CLAUDE_PROFILE_DISABLE_OPEN=1 \
         CLAUDE_PROFILE_MOCK_RUNNING="$MOCK" \
         CLAUDE_PROFILE_MOCK_DESKTOP="$DMOCK" \
         CLAUDE_PROFILE_MOCK_CODE="$CMOCK" \
            bash "$SCRIPT" "$@" $stdin_arg 2>/tmp/cp_err)"
  CODE=$?
  ERR="$(cat /tmp/cp_err 2>/dev/null)"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1)); echo "PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $desc"
    echo "  expected: [$expected]"
    echo "  actual:   [$actual]"
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1)); echo "PASS: $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $desc (missing: $needle)"
    echo "  output: $haystack"
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    FAIL=$((FAIL + 1)); echo "FAIL: $desc (unexpected: $needle)"
    echo "  output: $haystack"
  else
    PASS=$((PASS + 1)); echo "PASS: $desc"
  fi
}

assert_dir_exists() {
  local desc="$1" d="$1"
  shift
  if [[ -d "$BASE/$1" || -d "$CONF/$1" || -d "$CLHOME/$1" ]]; then :; fi
  # caller passes absolute-ish path resolved against BASE/CONF/CLHOME
  if [[ -d "$1" ]]; then PASS=$((PASS+1)); echo "PASS: $desc"
  else FAIL=$((FAIL+1)); echo "FAIL: $desc (missing dir: $1)"; fi
}

assert_dir_missing() {
  local desc="$1" d="$1"
  if [[ ! -d "$1" ]]; then PASS=$((PASS+1)); echo "PASS: $desc"
  else FAIL=$((FAIL+1)); echo "FAIL: $desc (dir present: $1)"; fi
}

assert_symlink() {
  local desc="$1" p="$2"
  if [[ -L "$p" ]]; then PASS=$((PASS+1)); echo "PASS: $desc"
  else FAIL=$((FAIL+1)); echo "FAIL: $desc (not a symlink: $p)"; fi
}

assert_not_symlink() {
  local desc="$1" p="$2"
  if [[ ! -L "$p" && -e "$p" ]]; then PASS=$((PASS+1)); echo "PASS: $desc"
  elif [[ ! -e "$p" ]]; then PASS=$((PASS+1)); echo "PASS: $desc (absent, ok)"
  else FAIL=$((FAIL+1)); echo "FAIL: $desc (is a symlink: $p)"; fi
}

assert_symlink_target() {
  local desc="$1" p="$2" want="$3"
  local got
  got="$(readlink "$p" 2>/dev/null || true)"
  if [[ "$got" == "$want" ]]; then PASS=$((PASS+1)); echo "PASS: $desc"
  else FAIL=$((FAIL+1)); echo "FAIL: $desc"; echo "  expected: [$want]"; echo "  actual:   [$got]"; fi
}

assert_file_json() {
  local desc="$1" file="$2" needle="$3"
  if grep -qF -- "$needle" "$file" 2>/dev/null; then PASS=$((PASS+1)); echo "PASS: $desc"
  else FAIL=$((FAIL+1)); echo "FAIL: $desc (missing in $file: $needle)"; fi
}

setup() { BASE="$(mktemp -d)"; CONF="$(mktemp -d)"; CLHOME="$(mktemp -d)/claudehome"; OLD_CONFIG="$(mktemp -d)/oldconfig"; }
teardown() { rm -rf -- "$BASE" "$CONF" "$(dirname "$CLHOME")" "$(dirname "$OLD_CONFIG")" /tmp/cp_err 2>/dev/null || true; }

# ---------------------------------------------------------------------------
echo "=== Test 1: add creates a sparse profile (no component dirs) ==="
setup
MOCK=0 run_out add work
assert_eq "add exit 0" "0" "$CODE"
assert_dir_exists "profile dir" "$CONF/accounts/work"
# A bare add must NOT create desktop/ or code/ automatically (profiles are sparse).
assert_dir_missing "no desktop subdir auto-created" "$CONF/accounts/work/desktop"
assert_dir_missing "no code subdir auto-created" "$CONF/accounts/work/code"
# add must NOT create active symlinks automatically
assert_not_symlink "no desktop symlink yet" "$BASE/Claude"
assert_not_symlink "no code symlink yet" "$CLHOME"
assert_file_json "config has profiles.work" "$CONF/config.json" '"work"'
teardown

echo "=== Test 2: activate Desktop only -> Application Support/Claude is a symlink ==="
setup
MOCK=0 run_out desktop add work
assert_eq "desktop add exit 0" "0" "$CODE"
MOCK=0 run_out activate work
assert_eq "activate exit 0" "0" "$CODE"
assert_symlink "Claude is symlink" "$BASE/Claude"
assert_symlink_target "Claude points to profile desktop" "$BASE/Claude" "$CONF/accounts/work/desktop"
assert_not_symlink "code symlink not created (no code profile)" "$CLHOME"
teardown

echo "=== Test 3: activate Code only -> ~/.claude is a symlink ==="
setup
MOCK=0 run_out code add work
assert_eq "code add exit 0" "0" "$CODE"
MOCK=0 run_out activate work
assert_eq "activate exit 0" "0" "$CODE"
assert_symlink "~/.claude is symlink" "$CLHOME"
assert_symlink_target "~/.claude points to profile code" "$CLHOME" "$CONF/accounts/work/code"
assert_not_symlink "desktop symlink not created (no desktop profile)" "$BASE/Claude"
teardown

echo "=== Test 4: combined activate, desktop present / code missing ==="
setup
MOCK=0 run_out desktop add work
MOCK=0 run_out activate work
assert_eq "activate exit 0" "0" "$CODE"
assert_symlink "desktop activated" "$BASE/Claude"
assert_symlink_target "desktop target" "$BASE/Claude" "$CONF/accounts/work/desktop"
assert_not_symlink "code skipped" "$CLHOME"
assert_contains "warning: no Code profile" "does not have a Claude Code account" "$OUT"
teardown

echo "=== Test 5: combined activate, code present / desktop missing ==="
setup
MOCK=0 run_out code add work
MOCK=0 run_out activate work
assert_eq "activate exit 0" "0" "$CODE"
assert_symlink "code activated" "$CLHOME"
assert_symlink_target "code target" "$CLHOME" "$CONF/accounts/work/code"
assert_not_symlink "desktop skipped" "$BASE/Claude"
assert_contains "warning: no Desktop profile" "does not have a Claude Desktop account" "$OUT"
teardown

echo "=== Test 6: explicit command strictness (missing platform profile) ==="
setup
MOCK=0 run_out desktop add work
# code profile 'work' does not exist
MOCK=0 run_out code activate work
assert_eq "code activate missing -> exit 2" "2" "$CODE"
assert_contains "code activate error" 'Claude Code account "work" does not exist' "$ERR"
MOCK=0 run_out desktop activate ghost
assert_eq "desktop activate missing -> exit 2" "2" "$CODE"
assert_contains "desktop activate error" 'Claude Desktop account "ghost" does not exist' "$ERR"
teardown

echo "=== Test 7: legacy (real, non-symlink) Claude dir is detected ==="
setup
MOCK=0
mkdir -p "$BASE/Claude"
printf 'x' > "$BASE/Claude/marker"
run_out status
assert_contains "status notes legacy install" "legacy installation" "$OUT"
assert_contains "status notes migrate" "cam migrate" "$OUT"
teardown

echo "=== Test 8: migration converts legacy Desktop layout ==="
setup
MOCK=0
# Active account (unnamed) + one legacy inactive account.
mkdir -p "$BASE/Claude"
printf 'active-data' > "$BASE/Claude/active_marker"
mkdir -p "$BASE/Claude-work"
printf 'work-data' > "$BASE/Claude-work/work_marker"
MOCK=0 run_out migrate personal --force
assert_eq "migrate exit 0" "0" "$CODE"
assert_dir_exists "personal desktop migrated" "$CONF/accounts/personal/desktop"
assert_eq "active data preserved" "active-data" "$(cat "$CONF/accounts/personal/desktop/active_marker" 2>/dev/null)"
assert_dir_exists "work desktop migrated" "$CONF/accounts/work/desktop"
assert_eq "work data preserved" "work-data" "$(cat "$CONF/accounts/work/desktop/work_marker" 2>/dev/null)"
assert_symlink "Claude now symlink" "$BASE/Claude"
assert_symlink_target "Claude -> personal desktop" "$BASE/Claude" "$CONF/accounts/personal/desktop"
assert_file_json "config has personal" "$CONF/config.json" '"personal"'
assert_file_json "config has work" "$CONF/config.json" '"work"'
# Migration must never create a root-level code/ directory.
assert_dir_missing "no root-level code dir" "$CONF/code"
teardown

echo "=== Test 9: rename updates symlinks + config ==="
setup
MOCK=0 run_out desktop add work >/dev/null
MOCK=0 run_out code add work >/dev/null
MOCK=0 run_out activate work >/dev/null
MOCK=0 run_out rename work company
assert_eq "rename exit 0" "0" "$CODE"
assert_dir_exists "renamed profile dir" "$CONF/accounts/company"
assert_dir_missing "old profile dir gone" "$CONF/accounts/work"
assert_symlink "desktop symlink updated" "$BASE/Claude"
assert_symlink_target "desktop -> company" "$BASE/Claude" "$CONF/accounts/company/desktop"
assert_symlink "code symlink updated" "$CLHOME"
assert_symlink_target "code -> company" "$CLHOME" "$CONF/accounts/company/code"
assert_file_json "config has company" "$CONF/config.json" '"company"'
teardown

echo "=== Test 10: remove safety (headless refused; --force allows active removal) ==="
setup
MOCK=0 run_out desktop add work >/dev/null
MOCK=0 run_out code add work >/dev/null
MOCK=0 run_out desktop add personal >/dev/null
MOCK=0 run_out code add personal >/dev/null
MOCK=0 run_out activate work >/dev/null
# headless remove (no --force) refused
MOCK=0 run_out --headless remove work
assert_eq "headless remove refused" "1" "$CODE"
# --force allows removing the active profile
MOCK=0 run_out remove work --force
assert_eq "remove active --force exit 0" "0" "$CODE"
assert_dir_missing "active profile removed" "$CONF/accounts/work"
# non-active --force remove
MOCK=0 run_out remove personal --force
assert_eq "remove non-active --force exit 0" "0" "$CODE"
assert_dir_missing "non-active profile removed" "$CONF/accounts/personal"
teardown

echo "=== Test 11: remove with confirmation prompt (y) ==="
setup
MOCK=0 run_out desktop add work >/dev/null
MOCK=0 run_out code add work >/dev/null
MOCK=0 run_out desktop add personal >/dev/null
MOCK=0 run_out code add personal >/dev/null
# make 'personal' active so 'work' is removable
MOCK=0 run_out activate personal >/dev/null
MOCK=0 run_out remove work <<<"y"
assert_eq "remove with y exit 0" "0" "$CODE"
assert_dir_missing "profile removed via prompt" "$CONF/accounts/work"
teardown

echo "=== Test 12: list shows DESKTOP/CODE presence ==="
setup
MOCK=0 run_out add work >/dev/null
MOCK=0 run_out code add personal >/dev/null
MOCK=0 run_out list
assert_contains "header NAME" "NAME" "$OUT"
assert_contains "header DESKTOP" "DESKTOP" "$OUT"
assert_contains "header CODE" "CODE" "$OUT"
assert_contains "work row" "work" "$OUT"
assert_contains "personal row" "personal" "$OUT"
teardown

echo "=== Test 13: desktop/code scoped add + activate + status ==="
setup
MOCK=0 run_out desktop add solo >/dev/null
MOCK=0 run_out code add solo >/dev/null
MOCK=0 run_out desktop activate solo >/dev/null
MOCK=0 run_out desktop status
assert_contains "desktop status profile" "solo" "$OUT"
MOCK=0 run_out code activate solo >/dev/null
MOCK=0 run_out code status
assert_contains "code status profile" "solo" "$OUT"
# scope correctness: desktop list only shows desktop profiles
MOCK=0 run_out desktop add d1 >/dev/null
MOCK=0 run_out code add c1 >/dev/null
MOCK=0 run_out desktop list
assert_contains "desktop list shows d1" "d1" "$OUT"
assert_contains "desktop list shows solo" "solo" "$OUT"
teardown

echo "=== Test 14: headless activate blocked while Claude Desktop is running ==="
setup
MOCK=1 run_out desktop add work >/dev/null
MOCK=1 run_out code add work >/dev/null
MOCK=1 run_out --headless activate work
assert_eq "headless activate while running exit 7" "7" "$CODE"
assert_contains "headless running error" "Claude Desktop is running" "$ERR"
assert_not_symlink "no switch while running (headless)" "$BASE/Claude"
teardown

echo "=== Test 14b: headless desktop activate blocked while running ==="
setup
MOCK=1 run_out desktop add work >/dev/null
MOCK=1 run_out --headless desktop activate work
assert_eq "headless desktop activate while running exit 7" "7" "$CODE"
assert_not_symlink "no desktop switch while running (headless)" "$BASE/Claude"
teardown

echo "=== Test 14c: interactive activate, Claude not running -> switch succeeds ==="
setup
MOCK=0 run_out desktop add work >/dev/null
MOCK=0 run_out code add work >/dev/null
MOCK=0 run_out activate work
assert_eq "activate not running exit 0" "0" "$CODE"
assert_symlink "symlink created when not running" "$BASE/Claude"
assert_symlink_target "Claude target when not running" "$BASE/Claude" "$CONF/accounts/work/desktop"
teardown

echo "=== Test 14d: interactive desktop activate, running + user says yes -> quit/switch/relaunch ==="
setup
MOCK=1 run_out desktop add work >/dev/null
MOCK=1 run_out desktop activate work <<<"y"
assert_eq "desktop activate running+yes exit 0" "0" "$CODE"
assert_symlink "desktop switched after running+yes" "$BASE/Claude"
assert_symlink_target "desktop target after running+yes" "$BASE/Claude" "$CONF/accounts/work/desktop"
assert_contains "prompt shown" "Claude Desktop is currently running" "$OUT"
assert_contains "relaunched success" "reopened Claude Desktop" "$OUT"
teardown

echo "=== Test 14e: interactive desktop activate, running + user says no -> no switch ==="
setup
MOCK=1 run_out desktop add work >/dev/null
MOCK=1 run_out desktop activate work <<<"n"
assert_eq "desktop activate running+no exit 6" "6" "$CODE"
assert_not_symlink "no switch when user declines" "$BASE/Claude"
assert_contains "cancelled message" "Operation cancelled by user" "$ERR"
teardown

echo "=== Test 14f: --no-launch still works when Claude not running ==="
setup
MOCK=0 run_out desktop add work >/dev/null
MOCK=0 run_out --no-launch desktop activate work
assert_eq "no-launch activate exit 0" "0" "$CODE"
assert_symlink "symlink created with --no-launch" "$BASE/Claude"
assert_symlink_target "target with --no-launch" "$BASE/Claude" "$CONF/accounts/work/desktop"
teardown

echo "=== Test 14g: --launch default reopens Claude Desktop after switch (not running) ==="
setup
MOCK=0 run_out desktop add work >/dev/null
MOCK=0 run_out desktop activate work
assert_eq "launch activate exit 0" "0" "$CODE"
assert_symlink "symlink created with default launch" "$BASE/Claude"
assert_symlink_target "target with default launch" "$BASE/Claude" "$CONF/accounts/work/desktop"
teardown

echo "=== Test 16: scoped remove keeps the other platform ==="
setup
MOCK=0 run_out desktop add work >/dev/null
MOCK=0 run_out code add work >/dev/null
MOCK=0 run_out code remove work --force
assert_eq "code remove exit 0" "0" "$CODE"
assert_dir_missing "code subdir removed" "$CONF/accounts/work/code"
assert_dir_exists "desktop subdir kept" "$CONF/accounts/work/desktop"
assert_file_json "config keeps profile" "$CONF/config.json" '"work"'
MOCK=0 run_out desktop remove work --force
assert_eq "desktop remove exit 0" "0" "$CODE"
assert_dir_missing "whole profile gone" "$CONF/accounts/work"
teardown

echo "=== Test 17: migrate a real ~/.claude into a Code profile ==="
setup
MOCK=0
mkdir -p "$CLHOME"
printf 'code-data' > "$CLHOME/code_marker"
MOCK=0 run_out migrate personal --force
assert_eq "migrate real ~/.claude exit 0" "0" "$CODE"
assert_dir_exists "code profile migrated" "$CONF/accounts/personal/code"
assert_eq "code data preserved" "code-data" "$(cat "$CONF/accounts/personal/code/code_marker" 2>/dev/null)"
assert_symlink "~/.claude now symlink" "$CLHOME"
assert_symlink_target "~/.claude -> personal code" "$CLHOME" "$CONF/accounts/personal/code"
assert_file_json "config has personal" "$CONF/config.json" '"personal"'
# code status now reports the active profile and no legacy note
MOCK=0 run_out code status
assert_contains "code active after migrate" "personal" "$OUT"
if printf '%s' "$OUT" | grep -qF "legacy installation"; then
  FAIL=$((FAIL+1)); echo "FAIL: legacy note still present after migrate"
else
  PASS=$((PASS+1)); echo "PASS: no legacy note after migrate"
fi
teardown

echo "=== Test 18: CASE 1 - both products available, activate both ==="
setup
MOCK=0 CAM_DESKTOP=1 CAM_CODE=1 run_out desktop add work >/dev/null
MOCK=0 CAM_DESKTOP=1 CAM_CODE=1 run_out code add work >/dev/null
MOCK=0 CAM_DESKTOP=1 CAM_CODE=1 run_out activate work
assert_eq "activate both exit 0" "0" "$CODE"
assert_symlink "desktop symlink" "$BASE/Claude"
assert_symlink_target "desktop target" "$BASE/Claude" "$CONF/accounts/work/desktop"
assert_symlink "code symlink" "$CLHOME"
assert_symlink_target "code target" "$CLHOME" "$CONF/accounts/work/code"
teardown

echo "=== Test 19: CASE 2 - Desktop only (Code not installed) ==="
setup
MOCK=0 CAM_DESKTOP=1 CAM_CODE=0 run_out desktop add work >/dev/null
MOCK=0 CAM_DESKTOP=1 CAM_CODE=0 run_out code add work >/dev/null
MOCK=0 CAM_DESKTOP=1 CAM_CODE=0 run_out activate work
assert_eq "activate desktop-only exit 0" "0" "$CODE"
assert_symlink "desktop activated" "$BASE/Claude"
assert_symlink_target "desktop target" "$BASE/Claude" "$CONF/accounts/work/desktop"
assert_not_symlink "code symlink not created" "$CLHOME"
assert_contains "warning: Code not installed" "Claude Code is not installed" "$OUT"
teardown

echo "=== Test 20: CASE 3 - Code only (Desktop not installed) ==="
setup
MOCK=0 CAM_DESKTOP=0 CAM_CODE=1 run_out desktop add work >/dev/null
MOCK=0 CAM_DESKTOP=0 CAM_CODE=1 run_out code add work >/dev/null
MOCK=0 CAM_DESKTOP=0 CAM_CODE=1 run_out activate work
assert_eq "activate code-only exit 0" "0" "$CODE"
assert_symlink "code activated" "$CLHOME"
assert_symlink_target "code target" "$CLHOME" "$CONF/accounts/work/code"
assert_not_symlink "desktop symlink not created" "$BASE/Claude"
assert_contains "warning: Desktop not installed" "Claude Desktop is not installed" "$OUT"
teardown

echo "=== Test 21: CASE 4 - neither product installed ==="
setup
MOCK=0 CAM_DESKTOP=0 CAM_CODE=0 run_out desktop add work >/dev/null
MOCK=0 CAM_DESKTOP=0 CAM_CODE=0 run_out code add work >/dev/null
assert_eq "add works without products" "0" "$CODE"
MOCK=0 CAM_DESKTOP=0 CAM_CODE=0 run_out list
assert_eq "list works without products" "0" "$CODE"
MOCK=0 CAM_DESKTOP=0 CAM_CODE=0 run_out activate work
assert_eq "activate without products exit 0" "0" "$CODE"
assert_contains "warning: Desktop unavailable" "Claude Desktop is not installed" "$OUT"
assert_contains "warning: Code unavailable" "Claude Code is not installed" "$OUT"
assert_contains "warning: nothing activated" "nothing was activated" "$OUT"
teardown

echo "=== Test 22: explicit desktop activate works when Code is absent ==="
setup
MOCK=0 CAM_DESKTOP=1 CAM_CODE=0 run_out desktop add work >/dev/null
MOCK=0 CAM_DESKTOP=1 CAM_CODE=0 run_out desktop activate work
assert_eq "explicit desktop activate exit 0" "0" "$CODE"
assert_symlink "desktop symlink created" "$BASE/Claude"
teardown

echo "=== Test 23: old-location migration detection notice ==="
setup
MOCK=0
rm -rf "$CONF"                      # new home must not exist yet
mkdir -p "$OLD_CONFIG/profiles/work"
run_out status
assert_contains "notice: found old cam data" "Found old cam data" "$ERR"
assert_contains "notice: would like to migrate" "Would you like to migrate to" "$ERR"
assert_contains "notice: run cam migrate" "Run 'cam migrate'" "$ERR"
teardown

echo "=== Test 24: cam migrate moves the old location into the new home ==="
setup
MOCK=0 CAM_DESKTOP=1 CAM_CODE=1
rm -rf "$CONF"                      # new home must not exist yet
mkdir -p "$OLD_CONFIG/profiles/work/desktop" "$OLD_CONFIG/profiles/work/code"
printf '{"profiles":{"work":{}}}' > "$OLD_CONFIG/config.json"
run_out migrate --force
assert_eq "migrate old-location exit 0" "0" "$CODE"
assert_file_json "new config has profile" "$CONF/config.json" '"work"'
assert_dir_exists "profile migrated" "$CONF/accounts/work"
assert_dir_exists "desktop subdir migrated" "$CONF/accounts/work/desktop"
assert_dir_exists "code subdir migrated" "$CONF/accounts/work/code"
# Old location is gone; notice no longer appears.
run_out status
if printf '%s' "$ERR" | grep -qF "Found old cam data"; then
  FAIL=$((FAIL+1)); echo "FAIL: old-location notice still appears after migrate"
else
  PASS=$((PASS+1)); echo "PASS: no old-location notice after migrate"
fi
teardown

echo "=== Test 15: cannot overwrite an existing profile on rename ==="
setup
MOCK=0 run_out add work >/dev/null
MOCK=0 run_out add personal >/dev/null
MOCK=0 run_out rename work personal
assert_eq "rename overwrite rejected" "1" "$CODE"
assert_dir_exists "work still present" "$CONF/accounts/work"
assert_dir_exists "personal still present" "$CONF/accounts/personal"
teardown

# ---------------------------------------------------------------------------
# Sparse-profile storage model: the only canonical location is
# accounts/<account>/<component>; there is never a root-level code/ directory,
# and empty component directories are not created automatically.
# ---------------------------------------------------------------------------

echo "=== Test 25: sparse profiles - no root-level code dir, components on demand ==="
setup
MOCK=0 run_out add personal >/dev/null
assert_dir_missing "no desktop for bare add" "$CONF/accounts/personal/desktop"
assert_dir_missing "no code for bare add" "$CONF/accounts/personal/code"
# Desktop-only profile: only desktop/ is created.
MOCK=0 run_out desktop add personal >/dev/null
assert_dir_exists "desktop created on demand" "$CONF/accounts/personal/desktop"
assert_dir_missing "code still absent after desktop add" "$CONF/accounts/personal/code"
# Code-only profile: only code/ is created.
MOCK=0 run_out code add work >/dev/null
assert_dir_exists "code created on demand" "$CONF/accounts/work/code"
assert_dir_missing "desktop still absent for code-only" "$CONF/accounts/work/desktop"
# Combined activation of a desktop-only profile skips the missing Code component.
MOCK=0 CAM_DESKTOP=1 CAM_CODE=1 run_out activate personal
assert_eq "activate desktop-only exit 0" "0" "$CODE"
assert_symlink "desktop symlink created" "$BASE/Claude"
assert_not_symlink "code symlink skipped (no code profile)" "$CLHOME"
assert_contains "warning: no Code profile" "does not have a Claude Code account" "$OUT"
# There must never be a root-level code/ directory.
assert_dir_missing "no root-level code dir" "$CONF/code"
teardown

# ---------------------------------------------------------------------------
# Regression: split-into-modules refactor must preserve behavior.
# ---------------------------------------------------------------------------

echo "=== Regression 1: entrypoint loads all modules ==="
setup
MOCK=0 run_out --help
assert_eq "help loads all modules (exit 0)" "0" "$CODE"
if printf '%s' "$ERR" | grep -qiE 'not found|no such file|command not found'; then
  FAIL=$((FAIL+1)); echo "FAIL: module load error present on stderr"; echo "  err: $ERR"
else
  PASS=$((PASS+1)); echo "PASS: no module load errors"
fi
teardown

echo "=== Regression 2: missing lib directory produces a clear error ==="
ISODIR="$(mktemp -d)"
cp "$SCRIPT" "$ISODIR/cam"
rm -rf "$ISODIR/lib"
OUT2="$(cd "$ISODIR" && bash ./cam status 2>&1)"; RC2=$?
if printf '%s' "$OUT2" | grep -qi 'lib'; then
  PASS=$((PASS+1)); echo "PASS: clear lib error message"
else
  FAIL=$((FAIL+1)); echo "FAIL: no clear lib error (output: $OUT2)"
fi
assert_eq "missing lib dir exit non-zero" "1" "$RC2"
rm -rf "$ISODIR"

echo "=== Regression 3: environment overrides still work ==="
setup
MOCK=0 CAM_DESKTOP=1 CAM_CODE=1 run_out add work >/dev/null
assert_eq "add honors overridden home" "0" "$CODE"
assert_dir_exists "profile created under overridden home" "$CONF/accounts/work"
assert_file_json "config written under overridden home" "$CONF/config.json" '"work"'
teardown

echo "=== Regression 4: temporary directories isolate data ==="
setup
MOCK=0 run_out add work >/dev/null
assert_dir_exists "profile present in first env" "$CONF/accounts/work"
teardown
# A fresh, independent temporary environment must not see the previous one.
setup
MOCK=0 run_out list
assert_eq "fresh env list exit 0" "0" "$CODE"
if printf '%s' "$OUT" | grep -q 'work'; then
  FAIL=$((FAIL+1)); echo "FAIL: data leaked across temporary environments"
else
  PASS=$((PASS+1)); echo "PASS: no data leak across temporary environments"
fi
teardown

# ---------------------------------------------------------------------------
# Claude Code running-process handling during activation.
# ---------------------------------------------------------------------------

echo "=== Test 26: headless code activate blocked while Claude Code is running ==="
setup
MOCK=0 CAM_CODE=1 CAM_MOCK_CODE_RUNNING=1 run_out code add work >/dev/null
MOCK=0 CAM_CODE=1 CAM_MOCK_CODE_RUNNING=1 run_out --headless code activate work
assert_eq "headless code activate while running exit 7" "7" "$CODE"
assert_contains "headless code running error" "Claude Code appears to be running" "$ERR"
assert_not_symlink "no code switch while running (headless)" "$CLHOME"
teardown

echo "=== Test 26b: headless combined activate blocked while Claude Code is running ==="
setup
MOCK=0 CAM_CODE=1 CAM_MOCK_CODE_RUNNING=1 run_out code add work >/dev/null
MOCK=0 CAM_CODE=1 CAM_MOCK_CODE_RUNNING=1 run_out --headless activate work
assert_eq "headless combined activate while code running exit 7" "7" "$CODE"
assert_not_symlink "no code switch in combined (headless)" "$CLHOME"
teardown

echo "=== Test 26c: interactive code activate, not running -> switch succeeds ==="
setup
MOCK=0 CAM_CODE=1 run_out code add work >/dev/null
MOCK=0 CAM_CODE=1 run_out code activate work
assert_eq "code activate not running exit 0" "0" "$CODE"
assert_symlink "code symlink created when not running" "$CLHOME"
assert_symlink_target "code target when not running" "$CLHOME" "$CONF/accounts/work/code"
assert_contains "switch message" "Switched Claude Code account" "$OUT"
assert_contains "no auto-relaunch message" "Start a new Claude Code session" "$OUT"
teardown

echo "=== Test 26d: interactive code activate, SIGTERM works -> switch succeeds ==="
setup
MOCK=0 CAM_CODE=1 CAM_MOCK_CODE_RUNNING=1 CAM_MOCK_CODE_PIDS="123 456" run_out code add work >/dev/null
MOCK=0 CAM_CODE=1 CAM_MOCK_CODE_RUNNING=1 CAM_MOCK_CODE_PIDS="123 456" run_out code activate work <<<"y"
assert_eq "code activate running+yes exit 0" "0" "$CODE"
assert_symlink "code switched after running+yes" "$CLHOME"
assert_symlink_target "code target after running+yes" "$CLHOME" "$CONF/accounts/work/code"
assert_contains "prompt shown" "Claude Code appears to be running" "$OUT"
teardown

echo "=== Test 26e: interactive code activate, running + user says no -> no switch ==="
setup
MOCK=0 CAM_CODE=1 CAM_MOCK_CODE_RUNNING=1 run_out code add work >/dev/null
MOCK=0 CAM_CODE=1 CAM_MOCK_CODE_RUNNING=1 run_out code activate work <<<"n"
assert_eq "code activate running+no exit 6" "6" "$CODE"
assert_not_symlink "no code switch when user declines" "$CLHOME"
assert_contains "cancelled message" "Operation cancelled by user" "$ERR"
teardown

echo "=== Test 26f: SIGTERM fails, force (SIGKILL) succeeds -> switch succeeds ==="
setup
MOCK=0 CAM_CODE=1 CAM_MOCK_CODE_RUNNING=1 CAM_MOCK_CODE_PIDS="123 456" CAM_MOCK_CODE_FORCE_REQUIRED=1 run_out code add work >/dev/null
MOCK=0 CAM_CODE=1 CAM_MOCK_CODE_RUNNING=1 CAM_MOCK_CODE_PIDS="123 456" CAM_MOCK_CODE_FORCE_REQUIRED=1 run_out code activate work <<<$'y\ny'
assert_eq "code activate force-terminate exit 0" "0" "$CODE"
assert_symlink "code switched after force-terminate" "$CLHOME"
assert_symlink_target "code target after force-terminate" "$CLHOME" "$CONF/accounts/work/code"
assert_contains "force prompt shown" "Force terminate them" "$ERR"
teardown

echo "=== Test 26g: SIGTERM fails, user declines force -> no switch, exit 6 ==="
setup
MOCK=0 CAM_CODE=1 CAM_MOCK_CODE_RUNNING=1 CAM_MOCK_CODE_PIDS="123 456" CAM_MOCK_CODE_FORCE_REQUIRED=1 run_out code add work >/dev/null
MOCK=0 CAM_CODE=1 CAM_MOCK_CODE_RUNNING=1 CAM_MOCK_CODE_PIDS="123 456" CAM_MOCK_CODE_FORCE_REQUIRED=1 run_out code activate work <<<$'y\nn'
assert_eq "code activate decline-force exit 6" "6" "$CODE"
assert_not_symlink "no code switch when force declined" "$CLHOME"
teardown

echo "=== Test 26h: code not installed -> skipped without running dance ==="
setup
MOCK=0 CAM_CODE=0 run_out code add work >/dev/null
MOCK=0 CAM_CODE=0 run_out code activate work
assert_eq "code activate not-installed exit 0" "0" "$CODE"
assert_contains "code not-installed warning" "Claude Code is not installed" "$OUT"
assert_not_symlink "no code symlink when product absent" "$CLHOME"
assert_not_contains "no running prompt when product absent" "Claude Code appears to be running" "$OUT"
teardown

# ---------------------------------------------------------------------------
echo
echo "=========================================="
echo "RESULTS: $PASS passed, $FAIL failed"
echo "=========================================="
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
