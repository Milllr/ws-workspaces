#!/usr/bin/env bash
# ws installer (macOS / zsh). Idempotent — safe to re-run.
#   bash macos/install.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/.config/ws"

echo "==> installing ws to $DEST"
mkdir -p "$DEST" "$HOME/worktrees"
cp "$REPO/macos/ws.zsh"               "$DEST/ws.zsh"
cp "$REPO/macos/idea_open.applescript" "$DEST/idea_open.applescript"
cp "$REPO/common/gen_override.py"     "$DEST/gen_override.py"

ZSHRC="$HOME/.zshrc"
touch "$ZSHRC"
if grep -q 'config/ws/ws.zsh' "$ZSHRC"; then
  echo "==> ~/.zshrc already wired, skipping"
else
  echo "==> wiring ws into ~/.zshrc"
  cat "$REPO/macos/zshrc-snippet.zsh" >> "$ZSHRC"
fi

# Keep the .ws-autoclaude marker out of `git status` everywhere.
if [ -z "$(git config --global core.excludesfile || true)" ]; then
  git config --global core.excludesfile "$HOME/.gitignore_global"
fi
GEXCL="$(git config --global core.excludesfile)"; GEXCL="${GEXCL/#\~/$HOME}"
touch "$GEXCL"
grep -qxF '.ws-autoclaude' "$GEXCL" || printf '\n# ws workspace marker\n.ws-autoclaude\n' >> "$GEXCL"

echo "==> done. Open a new terminal (or: source ~/.zshrc), then: ws -n my-branch"
echo "    First run will ask macOS for Accessibility + Automation permission — see README."
