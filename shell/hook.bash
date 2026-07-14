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

# The marker is a QUEUE (one launch spec per line). Each new terminal pops the
# first line, so N terminals resume N Claude sessions.
_ws_autostart() {
  case $- in *i*) ;; *) return ;; esac   # interactive only
  local m="$PWD/.ws-autoclaude"
  [ -f "$m" ] && [ -z "${WS_CLAUDE_STARTED:-}" ] || return
  if [ -n "$(find "$m" -mmin +${WS_MARKER_TTL:-1440} 2>/dev/null)" ]; then command rm -f "$m"; return; fi
  export WS_CLAUDE_STARTED=1
  local spec rest mode payload
  spec="$(head -n1 "$m" 2>/dev/null)"
  rest="$(tail -n +2 "$m" 2>/dev/null)"
  if [ -n "$rest" ]; then printf '%s\n' "$rest" > "$m"; else command rm -f "$m"; fi
  command -v claude >/dev/null 2>&1 || return
  mode="${spec%% *}"
  case "$spec" in
    *" "*) payload="${spec#* }" ;;
    *)     payload="" ;;
  esac
  case "$mode" in
    continue) claude --continue ;;
    resume)   claude --resume "$payload" ;;
    prompt)   claude "$payload" ;;
    *)        claude ;;
  esac
}
_ws_autostart

_ws_bash_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local subs="new resume switch also update save restore sessions cd path ls list status rm remove seed docker doctor version help"
  local names; names="$("$_ws_bin" --list-names 2>/dev/null)"
  COMPREPLY=( $(compgen -W "$subs $names" -- "$cur") )
}
complete -F _ws_bash_complete ws 2>/dev/null
