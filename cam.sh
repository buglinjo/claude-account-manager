#!/usr/bin/env bash
#
# cam - manage multiple Claude accounts (Desktop + Code) via symlinked accounts.
#
# This file is the entrypoint only. All behavior lives in lib/*.sh, which are
# SOURCED (not executed/compiled) at startup. See README "Developer layout".

set -euo pipefail

# Locate this script's directory so module paths are independent of $PWD / $PATH.
# CAM_ROOT can be pre-set by a Homebrew wrapper; respect it if already defined.
CAM_ROOT="${CAM_ROOT:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"}"

# Safety: without the implementation modules cam cannot run. Fail clearly
# instead of producing a cryptic "command not found".
if [[ ! -d "$CAM_ROOT/lib" ]]; then
  printf '%s\n' "cam: required library directory not found: $CAM_ROOT/lib" >&2
  exit 1
fi

# Load modules in dependency order (each only defines functions / variables).
source "$CAM_ROOT/lib/constants.sh"
source "$CAM_ROOT/lib/common.sh"
source "$CAM_ROOT/lib/config.sh"
source "$CAM_ROOT/lib/accounts.sh"
source "$CAM_ROOT/lib/symlinks.sh"
source "$CAM_ROOT/lib/detection.sh"
source "$CAM_ROOT/lib/desktop.sh"
source "$CAM_ROOT/lib/code.sh"
source "$CAM_ROOT/lib/migration.sh"
source "$CAM_ROOT/lib/commands.sh"

main "$@"
