# Bash completion for cam
#
# Install: source this file, or copy it to a bash_completion.d directory:
#   sudo cp cam.bash /usr/local/etc/bash_completion.d/cam
#   echo 'source /usr/local/etc/bash_completion.d/cam' >> ~/.bashrc

_cam() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local global_flags="--headless --force --verbose --help"
    local top_commands="status list activate add rename remove migrate desktop code"
    local desktop_cmds="status list activate add rename remove"
    local code_cmds="status list activate add rename remove"

    # First word: top-level command or global flag.
    if [[ "$COMP_CWORD" -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$top_commands $global_flags" -- "$cur") )
        return 0
    fi

    local cmd="${COMP_WORDS[1]}"
    local sub="${COMP_WORDS[2]:-}"

    # `cam desktop ...` and `cam code ...` route into their subcommands.
    if [[ "$cmd" == "desktop" || "$cmd" == "code" ]]; then
        local sub_cmds="$desktop_cmds"
        [[ "$cmd" == "code" ]] && sub_cmds="$code_cmds"
        if [[ "$COMP_CWORD" -eq 2 ]]; then
            COMPREPLY=( $(compgen -W "$sub_cmds $global_flags" -- "$cur") )
            return 0
        fi
        case "$sub" in
            activate|remove)
                _cam_accounts ;;
            rename)
                if [[ "$prev" == "rename" ]]; then
                    _cam_accounts
                else
                    COMPREPLY=( $(compgen -W "$global_flags" -- "$cur") )
                fi ;;
            *)
                COMPREPLY=( $(compgen -W "$global_flags" -- "$cur") ) ;;
        esac
        return 0
    fi

    # Top-level (combined) commands operate on both Desktop and Code.
    case "$cmd" in
        activate|remove)
            _cam_accounts ;;
        rename)
            if [[ "$prev" == "rename" ]]; then
                _cam_accounts
            fi ;;
        *)
            COMPREPLY=( $(compgen -W "$global_flags" -- "$cur") ) ;;
    esac
}

# Raw profile names (directories under the accounts/ directory).
_cam_accounts_raw() {
    local home="${CLAUDE_PROFILE_CONFIG:-$HOME/.claude-account-manager}"
    if [[ -d "$home/accounts" ]]; then
        ( cd "$home/accounts" 2>/dev/null && for d in */; do
            [[ -d "$d" ]] && printf '%s\n' "${d%/}"
        done )
    fi
}

# Complete with known profile names.
_cam_accounts() {
    COMPREPLY=( $(compgen -W "$(_cam_accounts_raw)" -- "$cur") )
}

if command -v complete >/dev/null 2>&1; then
    complete -F _cam cam
fi
