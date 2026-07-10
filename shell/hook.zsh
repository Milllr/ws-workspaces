# ws — zsh integration. Installed to ~/.config/ws/hook.zsh and sourced from ~/.zshrc.
# Provides: (1) `ws cd` that changes THIS shell's dir, (2) auto-launch Claude in a
# freshly-opened workspace terminal, (3) tab-completion of workspace names.

# Absolute path to the installed script (no dependence on ~/.local/bin being on PATH).
_ws_bin="${WS_CONFIG_DIR:-$HOME/.config/ws}/ws"

# `ws cd <name>` changes the current shell's directory; all else -> the ws command.
ws() {
  if [ "$1" = "cd" ]; then
    shift
    local __d
    __d="$("$_ws_bin" path "$@")" || return
    [ -n "$__d" ] && cd "$__d"
  else
    "$_ws_bin" "$@"
  fi
}

# Auto-start Claude the first time an interactive shell opens in a workspace.
# `ws -n`/`ws -r` drop a one-shot .ws-autoclaude marker: line 1 = mode
# (fresh|continue|prompt), remaining lines = the prompt payload.
_ws_autostart() {
  [[ -o interactive ]] || return
  [[ -f "$PWD/.ws-autoclaude" && -z "$WS_CLAUDE_STARTED" ]] || return
  export WS_CLAUDE_STARTED=1
  local m="$PWD/.ws-autoclaude" mode payload
  mode="$(head -n1 "$m" 2>/dev/null)"
  payload="$(tail -n +2 "$m" 2>/dev/null)"
  command rm -f "$m"
  command -v claude >/dev/null 2>&1 || return
  case "$mode" in
    continue) claude --continue ;;
    prompt)   claude "$payload" ;;
    *)        claude ;;
  esac
}
_ws_autostart

# Completion: subcommands + this repo's workspace names.
_ws_zsh_complete() {
  local -a subs
  subs=(new resume switch also cd path ls list status rm remove seed docker doctor version help)
  (( CURRENT == 2 )) && compadd -- $subs
  compadd -- ${(f)"$("$_ws_bin" --list-names 2>/dev/null)"}
}
if (( $+functions[compdef] )); then compdef _ws_zsh_complete ws 2>/dev/null; fi
