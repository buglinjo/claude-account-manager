#!/usr/bin/env bash
#
# cam - shared constants and overridable paths.
#
# This file is SOURCED by the cam entrypoint. It must contain ONLY variable
# initializations (no command execution) so it is safe to load under
# `set -e` / `set -u`.

# --- Canonical home for ALL cam data (accounts + state) -----------------------
# Overridable for tests via CLAUDE_ACCOUNT_MANAGER_HOME.
CAM_HOME="${CLAUDE_ACCOUNT_MANAGER_HOME:-$HOME/.claude-account-manager}"

# Previous (pre-migration) location; used only for one-time migration detection.
# Overridable via CLAUDE_PROFILE_OLD_CONFIG.
OLD_CONFIG_HOME="${CLAUDE_PROFILE_OLD_CONFIG:-$HOME/.config/claude-account-manager}"

# Where the active Claude Desktop symlink lives (BASE_DIR/Claude).
# Overridable via CLAUDE_PROFILE_APP_SUPPORT.
BASE_DIR="${CLAUDE_PROFILE_APP_SUPPORT:-$HOME/Library/Application Support}"

# Where the active Claude Code symlink lives (~/.claude).
# Overridable via CLAUDE_PROFILE_CLUDE_HOME.
CLAUDE_HOME="${CLAUDE_PROFILE_CLUDE_HOME:-$HOME/.claude}"

# Derived paths (do not override these directly; override the sources above).
CONFIG_FILE="$CAM_HOME/config.json"
ACCOUNTS_DIR="$CAM_HOME/accounts"

# The active symlinks (source of truth for "what is active").
ACTIVE_DESKTOP="$BASE_DIR/Claude"
ACTIVE_CODE="$CLAUDE_HOME"

# Runtime flags (parsed from argv in main()).
HEADLESS=0
FORCE=0
VERBOSE=0
LAUNCH=1

# Exit codes (see also print_help). RUNNING is used when a Desktop switch is
# blocked because Claude Desktop is already running (headless mode).
RUNNING=7
