# ws — bash integration. Installed to ~/.config/ws/hook.bash and sourced from ~/.bashrc
# (also works for Git Bash / WSL). See hook.zsh for what each piece does.

_ws_bin="${WS_CONFIG_DIR:-$HOME/.config/ws}/ws"

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

_ws_autostart() {
  case $- in *i*) ;; *) return ;; esac   # interactive only
  [ -f "$PWD/.ws-autoclaude" ] && [ -z "${WS_CLAUDE_STARTED:-}" ] || return
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

_ws_bash_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local subs="new resume switch also cd path ls list status rm remove seed docker doctor version help"
  local names; names="$("$_ws_bin" --list-names 2>/dev/null)"
  COMPREPLY=( $(compgen -W "$subs $names" -- "$cur") )
}
complete -F _ws_bash_complete ws 2>/dev/null
