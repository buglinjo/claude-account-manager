#!/usr/bin/env bash
#
# cam - account filesystem discovery.
#
# A account is accounts/<name>/ with optional desktop/ and code/ sub-directories.

# Absolute path helpers.
account_dir()         { echo "$ACCOUNTS_DIR/$1"; }
desktop_account_dir() { echo "$ACCOUNTS_DIR/$1/desktop"; }
code_account_dir()    { echo "$ACCOUNTS_DIR/$1/code"; }

# Existence helpers.
account_exists()         { [[ -d "$(account_dir "$1")" ]]; }
desktop_account_exists() { [[ -d "$(desktop_account_dir "$1")" ]]; }
code_account_exists()    { [[ -d "$(code_account_dir "$1")" ]]; }

# All known account names, from disk (accounts/<name>/) and the config store.
# Disk wins on ordering; the result is sorted and de-duplicated.
account_names() {
  local tmp
  tmp="$(mktemp)"
  [[ -d "$ACCOUNTS_DIR" ]] || { rm -f -- "$tmp"; return 0; }
  shopt -s nullglob
  local d n
  for d in "$ACCOUNTS_DIR"/*/; do
    n="$(basename "$d")"
    [[ -n "$n" && "$n" != .* ]] && echo "$n" >> "$tmp"
  done
  shopt -u nullglob
  config_list_accounts >> "$tmp"
  sort -u "$tmp"
  rm -f -- "$tmp"
}
