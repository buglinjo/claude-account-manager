# cam

A safe macOS command-line utility to manage **multiple Claude accounts** — both
**Claude Desktop** and **Claude Code** — from one tool.

## Why this exists

Claude Desktop stores all of its data (login, settings, history) in a single
Application Support directory, and Claude Code stores its data in `~/.claude`.
Neither has a built-in notion of multiple named, switchable accounts.

`cam` gives you **isolated, named accounts** that work for *both* products at
once, so one account name (`work`, `personal`, …) maps to a Desktop account
**and** a Code account. Switching is done by repointing **symlinks** — your data
is never copied or duplicated, and Claude Code picks up the active account
automatically via `~/.claude` (no environment variables, no `eval`, no `PATH`
tricks).

- **Account NAMES are shared** between Desktop and Code. `cam <command>` operates
  on both at once; `cam desktop <command>` / `cam code <command>` scope the
  command to a single product.
- The **active account is a symlink**: `~/Library/Application Support/Claude`
  points at `…/accounts/<name>/desktop`, and `~/.claude` points at
  `…/accounts/<name>/code`.
- A account need not have both a Desktop and a Code sub-account. Commands that
  touch a missing platform sub-account just warn and skip it (combined commands)
  or error (explicit `desktop`/`code` commands).

## Installation

Requires macOS and `python3` (for the metadata config store). Both ship with macOS.

### Homebrew

```bash
brew tap buglinjo/claude-account-manager
brew install claude-account-manager

# verify
cam --help
```

To upgrade later:

```bash
brew update && brew upgrade claude-account-manager
```

### Manual

```bash
# copy into a directory on your PATH (requires write access)
sudo cp cam /usr/local/bin/cam
sudo chmod +x /usr/local/bin/cam

# verify
cam --help
```

Or run directly with `bash cam ...`.

## Shell completions

Completion scripts for **bash** and **zsh** live in `completions/`.

- `completions/cam.bash` — bash completion
- `completions/_cam` — zsh completion (must be named with a leading underscore
  for `fpath`)

They complete subcommands, global flags, and **account names** for
`activate` / `remove` / `rename` (and the *old* name for `rename`).

### Bash

```bash
# system-wide
sudo cp completions/cam.bash /usr/local/etc/bash_completion.d/cam

# or per-user (add to ~/.bashrc / ~/.bash_account)
source /path/to/claude-account-manager/completions/cam.bash
```

### Zsh

```bash
# copy into a directory on your $fpath (note the leading underscore name)
mkdir -p ~/.zsh/completions
cp completions/_cam ~/.zsh/completions/

# ensure the dir is on fpath, then re-init (add to ~/.zshrc if needed)
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

> Both completion scripts read account names straight from
> `~/.claude-account-manager/accounts/*` (overridable via
> `CLAUDE_ACCOUNT_MANAGER_HOME`), so they work without launching the tool.

## Quick start

```bash
# 1. Create a account (creates desktop/ and code/ sub-directories)
cam add work

# 2. Switch the active account (repoints symlinks; no copy/move)
cam activate work

# 3. Just use Claude normally — it reads the active account via the symlink
claude           # Claude Code uses ~/.claude -> accounts/work/code
# open "Claude" from Applications — Claude Desktop uses the desktop symlink
```

That's it. There are **no environment variables to set and no `eval`** — the
symlinks are the single source of truth.

## Commands

### Combined (`cam ...`) — operates on BOTH Desktop and Code

| Command | Description |
| --- | --- |
| `cam status` | Show the active account for Desktop and Code (and symlink targets). |
| `cam list` | List all accounts with their Desktop / Code presence. |
| `cam add <name>` | Create a account with `desktop/` **and** `code/` sub-directories. |
| `cam rename <old> <new>` | Rename a account (updates symlinks if active). |
| `cam remove <name>` | Remove a account (prompts; `--force` bypasses; active account needs `--force`). |
| `cam activate <name>` | Repoint both symlinks to `<name>` (non-strict: warns and skips a missing platform). |
| `cam migrate [<name>]` | Convert a legacy (pre-`cam`) installation into accounts. Requires confirmation or `--force`. |

### Desktop (`cam desktop ...`)

| Command | Description |
| --- | --- |
| `cam desktop status` | Show the active Desktop account + symlink target. |
| `cam desktop list` | List Desktop accounts (active / logged-in state). |
| `cam desktop add <name>` | Create (or add Desktop to) a account, with a `desktop/` sub-directory. |
| `cam desktop activate <name>` | Repoint the Desktop symlink (strict: errors if the account has no Desktop sub-directory). |
| `cam desktop rename <old> <new>` | Rename a account. |
| `cam desktop remove <name>` | Remove a account's Desktop sub-directory (prompted; `--force` bypasses). |

### Code (`cam code ...`)

| Command | Description |
| --- | --- |
| `cam code status` | Show the active Code account + symlink target. |
| `cam code list` | List Code accounts (name / logged-in state). |
| `cam code add <name>` | Create (or add Code to) a account, with a `code/` sub-directory. |
| `cam code activate <name>` | Repoint the Code symlink. If a Claude Code session is running, `cam` prompts to terminate it first (see below). |
| `cam code rename <old> <new>` | Rename a account. |
| `cam code remove <name>` | Remove a account's Code sub-directory (prompted; `--force` bypasses). |

### Flags

| Flag | Effect |
| --- | --- |
| `--headless` | Never prompt; return errors via exit codes only. |
| `--force` | Bypass confirmation prompts (e.g. for `remove` / `migrate`); also allows removing the active account. |
| `--launch` | Reopen Claude Desktop after switching (default). |
| `--no-launch` | Do not reopen Claude Desktop after switching. |
| `--verbose` | Show detailed operations. |
| `--help` / `-h` | Show usage. |

**Claude Desktop is already running.** Because the active account is a symlink,
an already-open Claude keeps reading the *previous* account's data until it is
restarted. To avoid a confusing state (filesystem says one account is active
while the running app uses another), `cam` handles this explicitly when
activating a Desktop account:

- **Interactive mode** — `cam` detects that Claude Desktop is running and
  prompts:

  ```
  Claude Desktop is currently running.
  Close Claude Desktop, switch accounts, and reopen it with the new account? [Y/n]
  ```

   If you accept, `cam` gracefully quits Claude, waits for it to exit, repoints
   the symlink, and reopens Claude with the new account. If you decline, the
   switch is cancelled (exit 6) and nothing changes.
- **Headless mode** (`--headless`) — `cam` does **not** prompt and does **not**
   switch; it prints an error and exits with code 7 so the caller can decide.

**Claude Code is already running.** Unlike Claude Desktop, Claude Code is a
long-running CLI process with an in-memory session, so `cam` **never
auto-restarts it**. When you activate a Code account while a Claude Code session
is running, `cam` handles it explicitly:

- **Interactive mode** — `cam` detects that Claude Code is running and prompts:

  ```
  Claude Code appears to be running.
  Close all Claude Code sessions before switching accounts? [Y/n]
  ```

  If you accept, `cam` sends `SIGTERM` to the Claude Code processes, waits for
  them to exit, and repoints the symlink. If any process does not exit cleanly it
  asks again:

  ```
  Some Claude Code processes did not exit cleanly.
  Force terminate them? [y/N]
  ```

  A force-terminate (`SIGKILL`) is then sent before repointing the symlink.
  After switching, `cam` prints a reminder to start a new Claude Code session
  against the selected account — it does **not** launch one for you. If you
  decline either prompt, the switch is cancelled (exit 6) and nothing changes.
- **Headless mode** (`--headless`) — `cam` does **not** prompt and does **not**
  switch; it prints an error and exits with code 7 so the caller can decide.

When Claude Desktop is **not** running, the switch happens immediately and
Claude is reopened afterwards per `--launch` (default) / `--no-launch`.

## Migrating from a legacy installation (`cam migrate`)

`cam` manages two kinds of legacy data:

1. **Previous storage location.** `cam`'s data used to live at
   `~/.config/claude-account-manager`. The first time you run any `cam` command
   after installing the new version, it prints a notice if that old location
   still exists and the new `~/.claude-account-manager` does not:

   ```
   Found old cam data:
     ~/.config/claude-account-manager
   Would you like to migrate to:
     ~/.claude-account-manager
   Run 'cam migrate' to move it (data is never overwritten automatically).
   ```

   `cam migrate` moves the old directory into the new home (config + accounts)
   and never overwrites data that already exists in the new location.

2. **Pre-symlink Claude layouts.** Before `cam` switched to symlinks, you may
   have a real `~/Library/Application Support/Claude` directory (and possibly
   `Claude-<name>` directories), plus an old
   `~/.config/claude-account-manager/code/<name>` layout. `cam migrate` converts
   these into the account system without duplicating data.

```bash
# One-time migration. The active (unnamed) account becomes <name>; any
# Claude-<name> legacy accounts are also imported. Requires confirmation,
# or pass --force to skip the prompt.
cam migrate work
cam migrate --force
```

`migrate` will **never overwrite** an existing account. If the target account
directory already exists, the migration is skipped for that account with a
warning. After migrating, the active account is a symlink pointing at
`accounts/<name>/desktop`.

If `~/Library/Application Support/Claude` is a **real directory** (not a symlink)
when `cam` runs, `status` reports it as a legacy installation and tells you to
run `cam migrate` first. `cam` will not silently replace a real directory with a
symlink.

## Examples

```bash
# See the current state of both Desktop and Code
cam status

# Create a "work" account (desktop/ + code/)
cam add work

# Switch the active account (repoints symlinks)
cam activate work

# Create a Desktop-only account and activate just Desktop
cam desktop add meeting
cam activate meeting      # warns: "meeting" has no Code account, skips Code

# List every account with its Desktop/Code presence
cam list

# Rename a account (symlinks are updated if it's active)
cam rename work company

# Remove a account (prompts)
cam remove test

# Remove without prompting (e.g. in a script / CI)
cam remove test --force --headless

# Convert an existing real Claude installation into a account
cam migrate personal
```

### Example `cam status` output

```
Active account:
  work

Claude Desktop:
  Active account: work
  target: /Users/you/.config/claude-account-manager/accounts/work/desktop

Claude Code:
  Active account: work
  target: /Users/you/.config/claude-account-manager/accounts/work/code
```

### Example `cam list` output

```
NAME        DESKTOP  CODE
work        active   active
personal    yes      yes
meeting     yes      no
```

- **NAME** — the shared account name.
- **DESKTOP** — `active` (it is the active Desktop account), `yes` (it exists as
  a account with a `desktop/` sub-directory), or `no`.
- **CODE** — `active` / `yes` / `no` for the Code sub-account.

## How login detection works

A account sub-directory existing does **not** mean you are logged in. Login
status is detected independently by inspecting Claude's stored application data
(`Cookies`, `Local Storage`, `IndexedDB` for Desktop; `.credentials.json`,
`.claude.json`, or a non-empty `projects/` for Code). The detector returns only
`yes` / `no` / `unknown` and **never exposes tokens or credentials**.

The detection logic is isolated in the `is_logged_in()` (Desktop) and
`code_is_logged_in()` (Code) functions, so it can be updated later if Claude
changes its storage format without touching the rest of the tool.

## How accounts are stored

`cam` is the canonical owner of all Claude account data. Its home is a single
directory:

### Accounts (permanent directories)

```
~/.claude-account-manager/
├── config.json                 # metadata: account names (+ optional displayName)
├── accounts/                   # all accounts live here, permanently
│   ├── work/
│   │   ├── desktop/            # Claude Desktop data for "work"
│   │   └── code/               # Claude Code data for "work"
│   ├── personal/
│   │   ├── desktop/
│   │   └── code/
│   └── experiment/
│       └── code/               # Code-only account (no desktop/ sub-directory)
├── backups/                    # optional
└── logs/                       # optional
```

The `accounts/` directory is the source of truth. A account may contain only a
`desktop/` directory, only a `code/` directory, or both.

### Active account (symlinks — the single source of truth)

```
~/Library/Application Support/
└── Claude  ->  ~/.claude-account-manager/accounts/work/desktop

~/.claude    ->  ~/.claude-account-manager/accounts/work/code
```

Switching is a **single `ln -sfn`** of each symlink. There is one active account
at a time, and because the active account is just a symlink, Claude reads the
right data with no environment variables.

`~/.claude` is owned by `cam` only when a Code account is active; if you have a
pre-existing real `~/.claude` directory, `cam` treats it as a legacy
installation (see [Migration](#migrating-from-a-legacy-installation-cam-migrate))
and will not silently replace it.

### Product availability

`cam` works whether or not Claude Desktop and/or Claude Code are installed:

- **Both installed** — `cam activate work` activates both.
- **Desktop only** — Desktop commands work; Code activation is skipped with a
  warning (`Claude Code is not installed`).
- **Code only** — Code commands work; Desktop activation is skipped with a
  warning (`Claude Desktop is not installed`).
- **Neither installed** — `cam` still manages accounts (`add`, `list`,
  `rename`, `remove`); `activate` prints warnings and does not fail.

### Config

`config.json` stores only account names (optionally with a human-friendly
display name). There is **no** "active" state stored — the symlinks are the
source of truth.

```json
{
  "accounts": {
    "work":     { "displayName": "Company Claude" },
    "personal": { "displayName": "Personal Claude" }
  }
}
```

## Environment overrides (for testing / advanced use)

All paths can be overridden via environment variables (mainly used by the test
suite so it never touches real Claude data):

| Variable | Default |
| --- | --- |
| `CLAUDE_ACCOUNT_MANAGER_HOME` | `~/.claude-account-manager` |
| `CLAUDE_PROFILE_OLD_CONFIG` | `~/.config/claude-account-manager` (previous location, for migration) |
| `CLAUDE_PROFILE_APP_SUPPORT` | `~/Library/Application Support` |
| `CLAUDE_PROFILE_CLUDE_HOME` | `~/.claude` |
| `CLAUDE_PROFILE_MOCK_RUNNING` | (unset) set `1`/`0` to force Claude Desktop running detection |
| `CLAUDE_PROFILE_MOCK_DESKTOP` | (unset) set `1`/`0` to force Desktop availability |
| `CLAUDE_PROFILE_MOCK_CODE` | (unset) set `1`/`0` to force Code availability |
| `CLAUDE_PROFILE_DISABLE_OPEN` | (unset) set `1` to never open Claude Desktop |
| `CAM_MOCK_CODE_RUNNING` | (unset) set `1`/`0` to force Claude Code running detection |
| `CAM_MOCK_CODE_PIDS` | (unset) space-separated fake PIDs reported by `code_list_pids` |
| `CAM_MOCK_CODE_FORCE_REQUIRED` | (unset) set `1` so `SIGTERM` "fails" and the force (`SIGKILL`) prompt is exercised |

## Safety model

- Uses `set -euo pipefail`; **all paths are quoted** (spaces in `Application
  Support` are handled).
- Switching repoints **symlinks only** — directories are never copied or moved.
- The active account is a symlink; `cam` will **not** overwrite a real
  (non-symlink) directory — it reports a legacy installation and asks you to run
  `cam migrate`.
- The **active account can be removed only with `--force`**; without it, `remove`
  refuses (exit 3). In `--headless` mode without `--force`, `remove` refuses
  outright (exit 1).
- Renames/removals **cannot overwrite** an existing account.
- All account names are validated (letters, digits, `-`, `_`).
- When activating a Desktop account while Claude Desktop is running, `cam`
   prompts to quit/switch/reopen it (or, in `--headless`, refuses with exit 7).
- When activating a Code account while Claude Code is running, `cam` terminates
   the running session (SIGTERM, then SIGKILL if needed) before repointing — it
   never auto-relaunches Claude Code (or, in `--headless`, refuses with exit 7).

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `1` | Invalid arguments / operation refused (e.g. headless remove without `--force`) |
| `2` | Account does not exist |
| `3` | Invalid account state (e.g. removing the active account without `--force`) |
| `4` | (reserved) |
| `5` | File / symlink operation failed |
| `6` | User cancelled |
| `7` | Claude is running (a switch was blocked in headless mode — applies to both Desktop and Code) |

## Recovery instructions

Because accounts are plain directories and the active account is a symlink,
recovery is straightforward.

### Re-point a symlink manually

If a symlink ever points at the wrong place:

```bash
ln -sfn ~/.claude-account-manager/accounts/work/desktop \
        ~/Library/Application\ Support/Claude
ln -sfn ~/.claude-account-manager/accounts/work/code \
        ~/.claude
```

### If you deleted a account

Removed accounts are deleted with `rm -rf` and are **not** sent to the Trash.
Restore them from a Time Machine / backup of
`~/.claude-account-manager/accounts/<name>`.

### If `config.json` is lost

Account directories on disk remain intact. `cam` infers available accounts from
the `accounts/` directory; only the optional `displayName` metadata is lost.
Recreate the metadata by running `cam add <name>` again — since the account
directory already exists, it is simply re-registered (no data is overwritten).

## Troubleshooting

- **"This looks like a legacy installation. Run 'cam migrate' first."** — Your
  `~/Library/Application Support/Claude` (or `~/.claude`) is a real directory, not
  a symlink. Run `cam migrate <name>` to convert it.
- **Activation seems to do nothing.** — Restart Claude Desktop / Claude Code; an
  already-open app keeps reading the previous account until it reloads.
- **Login status shows `unknown`.** — The account sub-directory is missing or its
   storage layout is unrecognized. Login detection may need updating; the logic
   is isolated in `desktop_login_status()` / `code_login_status()` (in
   `lib/detection.sh`).
- **`python3` not found.** — Install Python 3 (e.g. via `brew install python`)
  so the metadata store works.
 - **Tests.** — Run the automated test suite, which uses temporary fake
   Application Support directories and never touches real Claude data:

   ```bash
   bash test_cam.sh
   ```

## Developer layout

`cam` is a single POSIX-ish Bash entrypoint that **sources** a set of modules at
startup. There is no build step and nothing is compiled — `lib/*.sh` are plain
shell fragments that define functions and variables, then `main` (in
`lib/commands.sh`) is called.

```
cam                 Entrypoint. Locates its own directory, sources every
                    module under lib/ in dependency order, then calls main().
                    Contains no business logic.

lib/                Implementation modules (sourced, not compiled):

  constants.sh      Canonical paths + runtime flags. The only place global
                    state is initialized.
  common.sh         Generic helpers (err/warn/vlog/prompt/confirm,
                    validate_account_name, login_short). No product logic.
  config.sh         JSON metadata store at $CAM_HOME/config.json.
  accounts.sh       Account filesystem discovery (account_dir / *_exists /
                    account_names).
  symlinks.sh       Symlink source-of-truth operations (make_symlink,
                    resolve_account, get_current_*, activate_*_account).
  detection.sh      External detection: product availability, running state,
                    login state. Fully mockable via env vars.
  desktop.sh        Claude Desktop behavior (desktop_status/list/add/
                     activate/rename/remove), shared platform_list, and Desktop
                     process management (desktop_is_running/quit/wait_for_exit/
                     launch/restart_for_activation). Mockable via env vars.
  code.sh           Claude Code behavior (same surface, code_*), plus Code
                      process management (code_is_running/list_pids/stop/
                      stop_force/wait_for_exit/restart_for_activation). Mockable
                      via CAM_MOCK_CODE_* env vars.
  migration.sh      Legacy-data migration (old location + pre-symlink layouts).
  commands.sh       Shared command implementations (do_*), combined
                    status/list, the desktop/code/combined subcommand
                    dispatchers, print_help, old-location notice, and main().

test_cam.sh         Automated test suite. Runs `cam` against temporary fake
                    Application Support / config / ~/.claude directories via
                    environment overrides. Never touches real Claude data.
```

### Modules are sourced, not compiled

Each `lib/*.sh` file is loaded with `source` into the same shell. That means:

- A module defines **functions and variables only** at load time — it must not
  execute commands that could fail (the entrypoint runs under `set -euo pipefail`).
- Functions call each other across modules freely; resolution happens at call
  time, after all modules are loaded, so source order only matters for variable
  initialization.
- Globals (paths, flags) live in `lib/constants.sh`. Everything else is a
  `prefix_`-namespaced function.

To add a feature (e.g. MCP accounts, plugin accounts, shared settings,
backup/restore), create or extend the most specific module and keep the entrypoint
untouched.
