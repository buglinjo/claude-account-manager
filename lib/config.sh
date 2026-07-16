#!/usr/bin/env bash
#
# cam - JSON config (metadata) store at $CONFIG_FILE.
#
# Only stores account names + display names. The active account state lives in
# the symlinks, NOT here. This module must not manage filesystem accounts.

# Echo the absolute path of the config file.
config_file() { echo "$CONFIG_FILE"; }

# Migrate a legacy config that used the "profiles" key to the new "accounts" key,
# preserving all metadata. Idempotent and never destructive.
config_migrate_schema() {
  local f; f="$(config_file)"
  [[ -f "$f" ]] || return 0
  python3 - "$f" <<'PY'
import json, sys
f = sys.argv[1]
try:
    d = json.load(open(f))
except Exception:
    sys.exit(0)
if "profiles" in d and "accounts" not in d:
    d["accounts"] = d.pop("profiles")
    json.dump(d, open(f, "w"), indent=2)
PY
}

# Create an empty config file (and its parent directory) if missing.
ensure_config() {
  local f
  f="$(config_file)"
  config_migrate_schema
  if [[ ! -f "$f" ]]; then
    mkdir -p -- "$CAM_HOME"
    printf '{}' > "$f"
  fi
}

# Print every account name stored in the config (one per line).
config_list_accounts() {
  local f
  f="$(config_file)"
  config_migrate_schema
  [[ ! -f "$f" ]] && return 0
  python3 - "$f" <<'PY'
import json, sys
f = sys.argv[1]
try:
    d = json.load(open(f))
except Exception:
    d = {}
for n in d.get("accounts", {}):
    print(n)
PY
}

# Register (idempotently) a account name in the config.
config_add_account() {
  local f; f="$(config_file)"; ensure_config
  python3 - "$f" "$1" <<'PY'
import json, sys
f, name = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(f))
except Exception:
    d = {}
d.setdefault("accounts", {})[name] = d.get("accounts", {}).get(name, {})
json.dump(d, open(f, "w"), indent=2)
PY
}

# Rename a account entry, preserving its metadata.
config_rename_account() {
  local f; f="$(config_file)"; ensure_config
  python3 - "$f" "$1" "$2" <<'PY'
import json, sys
f, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    d = json.load(open(f))
except Exception:
    d = {}
p = d.setdefault("accounts", {})
if old in p:
    p[new] = p.pop(old)
json.dump(d, open(f, "w"), indent=2)
PY
}

# Remove a account entry. Never fails if the entry is absent.
config_remove_account() {
  local f; f="$(config_file)"; ensure_config
  python3 - "$f" "$1" <<'PY'
import json, sys
f, name = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(f))
except Exception:
    d = {}
d.get("accounts", {}).pop(name, None)
json.dump(d, open(f, "w"), indent=2)
PY
}

# Print the display name for a account (empty string if none / absent).
config_display() {
  local f
  f="$(config_file)"
  config_migrate_schema
  [[ ! -f "$f" ]] && return 0
  python3 - "$f" "$1" <<'PY'
import json, sys
f, name = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(f))
except Exception:
    d = {}
print(d.get("accounts", {}).get(name, {}).get("displayName", ""))
PY
}
