
# ws — per-branch worktree workspaces (see ~/.config/ws/ws.zsh)
source "$HOME/.config/ws/ws.zsh"

# ws: auto-launch claude the first time a freshly-opened workspace terminal starts.
# `ws -n`/`ws -r` drop a one-shot .ws-autoclaude marker in the worktree root;
# the first interactive shell there consumes it and runs claude (with any saved args).
if [[ -o interactive && -f "$PWD/.ws-autoclaude" && -z "$WS_CLAUDE_STARTED" ]]; then
  export WS_CLAUDE_STARTED=1
  _ws_claude_args="$(< "$PWD/.ws-autoclaude")"
  command rm -f "$PWD/.ws-autoclaude"
  if command -v claude >/dev/null 2>&1; then
    claude ${=_ws_claude_args}
  fi
  unset _ws_claude_args
fi
