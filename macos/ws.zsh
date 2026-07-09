# ~/.config/ws/ws.zsh
# ws — per-branch git worktree "workspaces" that open in IntelliJ IDEA with Claude.
# Universal: run from inside any git repo. Worktrees live at $WS_HOME/<repo>/<name>.
#
# Usage:
#   ws -n <name> [base-ref]   create a new workspace (branch + worktree) and open it
#   ws -r [name]              resume a workspace (no name -> interactive picker)
#   ws                        same as `ws -r`
#   ws -l                     list this repo's worktrees
#   ws -rm [name]             remove a workspace (no name -> picker); keeps the branch
#   ws -h                     help
#
# Env knobs (override before use, e.g. in ~/.zshrc):
#   WS_HOME           base dir for worktrees                 (default: ~/worktrees)
#   WS_COPY           gitignored files to copy into new WS   (default: ".env")
#                     extra per-repo files: list paths (one per line) in
#                     ~/.config/ws/seed/<repo>.txt  (nested paths ok)
#   WS_IDEA_WAIT      secs to wait for the IntelliJ window   (default: 15)
#   WS_NO_UI=1        skip all IntelliJ/AppleScript automation (just create + `idea`)
#   WS_NO_MERGE=1     don't "Merge All Project Windows"
#   WS_NO_TERMINAL=1  don't auto-open the terminal / Claude

typeset -g WS_DIR="${${(%):-%x}:A:h}"
: ${WS_HOME:="$HOME/worktrees"}
: ${WS_COPY:=".env"}
: ${WS_IDEA_WAIT:=15}

_ws_in_repo() { git rev-parse --git-dir >/dev/null 2>&1 }

# Name of the *main* repo (works from the main checkout or any linked worktree).
_ws_repo_name() {
  local main
  main="$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)"
  [[ -n "$main" ]] || return 1
  print -r -- "${main:t}"
}

# Copy gitignored local files into a fresh worktree: WS_COPY (default .env) plus
# anything listed in ~/.config/ws/seed/<repo>.txt (one relative path per line).
_ws_seed_files() {
  local dir="$1" root repo f seedlist
  root="$(git rev-parse --show-toplevel)" || return
  repo="$(_ws_repo_name)"
  local -a files; files=(${(z)WS_COPY})
  seedlist="$WS_DIR/seed/$repo.txt"
  [[ -f "$seedlist" ]] && files+=("${(f)$(<"$seedlist")}")
  for f in $files; do
    [[ -n "$f" ]] || continue
    if [[ -e "$root/$f" && ! -e "$dir/$f" ]]; then
      mkdir -p "$dir/${f:h}" 2>/dev/null
      cp -R "$root/$f" "$dir/$f" && print -r -- "ws: seeded $f"
    fi
  done
}

# Write the one-shot marker read by ~/.zshrc to auto-launch claude.
# $2 = extra args for claude ("" = fresh session, "--continue" = resume).
_ws_mark() { print -r -- "$2" > "$1/.ws-autoclaude" }

# 0 (true) if an IntelliJ window title already contains $1.
_ws_window_open() {
  [[ "$OSTYPE" == darwin* ]] || return 1
  osascript - "$1" <<'OSA' 2>/dev/null | grep -q yes
on run argv
  set n to item 1 of argv
  tell application "System Events"
    try
      set proc to first process whose bundle identifier is "com.jetbrains.intellij"
    on error
      return "no"
    end try
    if (exists (first window of proc whose name contains n)) then
      return "yes"
    end if
  end tell
  return "no"
end run
OSA
}

# Open a worktree in IntelliJ, merge windows, open its terminal (which auto-runs claude).
_ws_open() {
  local dir="$1" name="$2" was_open=0
  if [[ "$OSTYPE" == darwin* && -z "$WS_NO_UI" ]] && _ws_window_open "$name"; then
    was_open=1
  fi
  idea "$dir" >/dev/null 2>&1 || { print -r -- "ws: 'idea' launcher failed (is the IntelliJ CLI on PATH?)"; return 1 }
  print -r -- "ws: $name -> $dir"
  if [[ "$OSTYPE" != darwin* || -n "$WS_NO_UI" ]]; then
    print -r -- "ws: opened in IntelliJ (UI automation off — press Opt+F12, then run: claude)"
    return 0
  fi
  local do_terminal=1 do_merge=1
  [[ -n "$WS_NO_TERMINAL" || $was_open -eq 1 ]] && do_terminal=0
  [[ -n "$WS_NO_MERGE" ]] && do_merge=0
  local err rc
  err="$(osascript "$WS_DIR/idea_open.applescript" "$name" "$do_terminal" "$do_merge" "$WS_IDEA_WAIT" 2>&1 >/dev/null)"; rc=$?
  if (( rc != 0 )); then
    print -r -- "ws: IntelliJ automation failed (${err:-no message})."
    print -r -- "    Grant the app you run 'ws' from (Terminal or IntelliJ IDEA) BOTH:"
    print -r -- "      System Settings -> Privacy & Security -> Accessibility   (toggle it ON)"
    print -r -- "      System Settings -> Privacy & Security -> Automation      (allow 'System Events')"
    print -r -- "    Then QUIT & REOPEN that app (Accessibility only applies after relaunch)."
    print -r -- "    Meanwhile: in IntelliJ press Opt+F12 and run: claude"
  fi
}

_ws_new() {
  local name="$1" base="$2"
  [[ -n "$name" ]] || { print -r -- "usage: ws -n <name> [base-ref]"; return 1 }
  _ws_in_repo || { print -r -- "ws: not inside a git repo"; return 1 }
  local repo dir; repo="$(_ws_repo_name)"; dir="$WS_HOME/$repo/$name"
  if [[ -e "$dir" ]]; then
    print -r -- "ws: workspace exists: $dir  (resume it: ws -r $name)"; return 1
  fi
  mkdir -p "$WS_HOME/$repo"
  if git show-ref --verify --quiet "refs/heads/$name"; then
    git worktree add "$dir" "$name" || return 1                          # existing local branch
  elif git ls-remote --exit-code --heads origin "$name" >/dev/null 2>&1; then
    git worktree add --track -b "$name" "$dir" "origin/$name" || return 1 # track remote branch
  else
    git worktree add -b "$name" "$dir" ${base:+"$base"} || return 1      # new branch off base/HEAD
  fi
  _ws_seed_files "$dir"
  _ws_mark "$dir" ""
  _ws_open "$dir" "$name"
}

# Print this repo's workspace names, one per line.
_ws_names() {
  local repo base; repo="$(_ws_repo_name)"; base="$WS_HOME/$repo"
  [[ -d "$base" ]] || return 0
  print -rl -- ${base}/*(/N:t)
}

_ws_pick() {
  local -a names; names=(${(f)"$(_ws_names)"})
  if (( ${#names} == 0 )); then
    print -r -- "ws: no workspaces for '$(_ws_repo_name)' — create one: ws -n <name>" >&2
    return 1
  fi
  print -r -- "workspaces for $(_ws_repo_name):" >&2
  local i
  for i in {1..${#names}}; do print -r -- "  $i) ${names[$i]}" >&2; done
  local choice; print -n -- "select [1-${#names}]: " >&2; read -r choice
  if [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#names} )); then
    print -r -- "${names[$choice]}"
  else
    print -r -- "ws: cancelled" >&2; return 1
  fi
}

_ws_resume() {
  _ws_in_repo || { print -r -- "ws: not inside a git repo"; return 1 }
  local name="$1"
  [[ -n "$name" ]] || name="$(_ws_pick)" || return 1
  local repo dir; repo="$(_ws_repo_name)"; dir="$WS_HOME/$repo/$name"
  [[ -d "$dir" ]] || { print -r -- "ws: no such workspace: $name"; return 1 }
  _ws_mark "$dir" "--continue"
  _ws_open "$dir" "$name"
}

_ws_list() {
  _ws_in_repo || { print -r -- "ws: not inside a git repo"; return 1 }
  print -r -- "worktrees for $(_ws_repo_name):"
  git worktree list
}

_ws_remove() {
  _ws_in_repo || { print -r -- "ws: not inside a git repo"; return 1 }
  local name="$1"
  [[ -n "$name" ]] || name="$(_ws_pick)" || return 1
  local repo dir; repo="$(_ws_repo_name)"; dir="$WS_HOME/$repo/$name"
  [[ -d "$dir" ]] || { print -r -- "ws: no such workspace: $name"; return 1 }
  if ! git worktree remove "$dir" 2>/dev/null; then
    print -r -- "ws: worktree busy or has changes. Force with: git worktree remove --force '$dir'"; return 1
  fi
  git worktree prune
  print -r -- "ws: removed workspace '$name'. Branch kept — delete with: git branch -D $name"
}

# ws -d [name] [slot|off] — isolate a workspace's Docker stack so several can run
# at once: namespaced container_names + offset host ports via a generated
# compose.override.yml (auto-merged by `make run`). Touches no tracked repo files.
_ws_docker() {
  _ws_in_repo || { print -r -- "ws: not inside a git repo"; return 1 }
  local name="$1" slot="${2:-0}" off_mode=0
  [[ "$1" == "off" ]] && { off_mode=1; name="$2"; }
  [[ "$2" == "off" ]] && off_mode=1
  [[ -n "$name" ]] || name="$(_ws_pick)" || return 1
  [[ "$slot" == <-> ]] || slot=0
  local repo dir; repo="$(_ws_repo_name)"; dir="$WS_HOME/$repo/$name"
  [[ -d "$dir" ]] || { print -r -- "ws: no such workspace: $name"; return 1 }

  local base="" f
  for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    [[ -f "$dir/$f" ]] && { base="$f"; break; }
  done
  [[ -n "$base" ]] || { print -r -- "ws: no compose file in $dir — nothing to isolate"; return 1 }
  local override="${base:r}.override.${base:e}"

  if (( off_mode )); then
    rm -f "$dir/$override" && print -r -- "ws: docker isolation OFF for '$name' (removed $override)"
    return 0
  fi

  command -v python3 >/dev/null 2>&1 || { print -r -- "ws: python3 not found (needed for ws -d)"; return 1 }
  local out
  out="$(python3 "$WS_DIR/gen_override.py" "$dir/$base" "$name" "$slot" "$repo")" || return 1

  # keep the generated override out of `git status` (repo-local, not committed)
  local excl; excl="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/info/exclude"
  [[ -f "$excl" ]] && { grep -qxF "$override" "$excl" 2>/dev/null || print -r -- "$override" >> "$excl"; }

  print -r -- "ws: docker isolation ON for '$name'  (project: $(print -r -- "$out" | sed -n 2p))"
  print -r -- "$out" | sed -n '3,$p' | sed 's/^port /  /'
  print -r -- "  run:     cd \"$dir\" && make run   (auto-merges $override)"
  print -r -- "  disable: ws -d $name off"
}

_ws_help() {
  print -r -- "ws — per-branch worktree workspaces (open in IntelliJ + Claude)
  ws -n <name> [base]   new workspace (branch + worktree), open it
  ws -r [name]          resume (no name -> picker)
  ws                    resume picker
  ws -l                 list worktrees
  ws -rm [name]         remove workspace (keeps branch)
  ws -d [name] [slot]   isolate docker stack for concurrent runs (slot 1-5; 'off' to disable)
  ws -h                 this help
worktrees live under: $WS_HOME/<repo>/<name>"
}

ws() {
  emulate -L zsh
  case "$1" in
    -n|--new)     shift; _ws_new "$@" ;;
    -r|--resume)  shift; _ws_resume "$@" ;;
    -l|--list)    shift; _ws_list ;;
    -rm|--remove) shift; _ws_remove "$@" ;;
    -d|--docker)  shift; _ws_docker "$@" ;;
    -h|--help)    _ws_help ;;
    "")           _ws_resume ;;
    -*)           print -r -- "ws: unknown option '$1'"; _ws_help; return 1 ;;
    *)            print -r -- "ws: unknown command '$1' (new workspace? ws -n \"$1\")"; return 1 ;;
  esac
}
