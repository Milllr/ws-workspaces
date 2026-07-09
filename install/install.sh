#!/usr/bin/env bash
# ws installer (macOS / Linux / Git Bash / WSL). Idempotent — safe to re-run.
#   bash install/install.sh
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${WS_CONFIG_DIR:-$HOME/.config/ws}"
BIN="$HOME/.local/bin"

echo "==> installing ws -> $DEST"
mkdir -p "$DEST" "$DEST/seed" "$BIN" "$HOME/worktrees"
cp "$REPO/bin/ws"                    "$DEST/ws";              chmod +x "$DEST/ws"
cp "$REPO/common/gen_override.py"    "$DEST/gen_override.py"
cp "$REPO/lib/idea_open.applescript" "$DEST/idea_open.applescript"
cp "$REPO/shell/hook.zsh"            "$DEST/hook.zsh"
cp "$REPO/shell/hook.bash"           "$DEST/hook.bash"
cp "$REPO/config.example"            "$DEST/config.example"
[ -f "$REPO/bin/ws.ps1" ] && cp "$REPO/bin/ws.ps1" "$DEST/ws.ps1"

ln -sf "$DEST/ws" "$BIN/ws"
echo "==> linked $BIN/ws -> $DEST/ws"
case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "    NOTE: $BIN is not on your PATH — add it, or rely on the shell hook." ;;
esac

# Wire an rc file with a replaceable sentinel block (also strips any v1 lines).
_wire() {  # $1 rcfile  $2 hookfile
  local rc="$1" hook="$2"
  [ -f "$rc" ] || return 0
  awk '
    /^# >>> ws >>>/ {skip=1}
    skip==1 { if (/^# <<< ws <<</) skip=0; next }
    /config\/ws\/ws\.zsh/ {next}          # drop legacy v1 source line
    {print}
  ' "$rc" > "$rc.wsnew" && mv "$rc.wsnew" "$rc"
  printf '\n# >>> ws >>>\nsource "%s"\n# <<< ws <<<\n' "$hook" >> "$rc"
  echo "==> wired $rc"
}
[ -f "$HOME/.zshrc" ]  && _wire "$HOME/.zshrc"  "$DEST/hook.zsh"
[ -f "$HOME/.bashrc" ] && _wire "$HOME/.bashrc" "$DEST/hook.bash"
# If neither exists, create the one matching the current shell.
if [ ! -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.bashrc" ]; then
  case "${SHELL:-}" in
    *zsh)  printf '\n# >>> ws >>>\nsource "%s"\n# <<< ws <<<\n' "$DEST/hook.zsh"  >> "$HOME/.zshrc";  echo "==> created ~/.zshrc" ;;
    *)     printf '\n# >>> ws >>>\nsource "%s"\n# <<< ws <<<\n' "$DEST/hook.bash" >> "$HOME/.bashrc"; echo "==> created ~/.bashrc" ;;
  esac
fi

# Keep the .ws-autoclaude marker out of `git status` everywhere.
if [ -z "$(git config --global core.excludesfile || true)" ]; then
  git config --global core.excludesfile "$HOME/.gitignore_global"
fi
GEXCL="$(git config --global core.excludesfile)"; GEXCL="${GEXCL/#\~/$HOME}"
touch "$GEXCL"
grep -qxF '.ws-autoclaude' "$GEXCL" || printf '\n# ws workspace marker\n.ws-autoclaude\n' >> "$GEXCL"

# Migrate a v1 install if present.
[ -f "$DEST/ws.zsh" ] && { rm -f "$DEST/ws.zsh"; echo "==> removed legacy ws.zsh"; }

echo "==> done. Open a new terminal (or: source your rc), then: ws doctor"
