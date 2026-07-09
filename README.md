# ws — per-branch workspaces for parallel Claude Code sessions

`ws` is a tiny universal shell command for working on **many branches of the same repo at once**,
each in its own directory, its own IntelliJ project tab, and its own Claude Code session — with no
branch switching, stashing, or clobbering.

```
ws -n "bug-1203-blank-image"   # new branch + worktree, opens in IntelliJ, Claude auto-starts
ws -r                          # pick an existing workspace to resume (Claude --continue)
ws -l                          # list this repo's workspaces
ws -rm bug-1203-blank-image    # tear one down (keeps the branch)
ws -d  bug-1203-blank-image    # (optional) isolate its Docker stack to run concurrently
```

It's built on **git worktrees** (one repo, many checked-out branches in separate folders, one shared
history) plus a thin layer that seeds local config, opens the folder in IntelliJ, and auto-launches
Claude. Works in **any git repo**. macOS (zsh) and Windows (PowerShell) are both supported.

---

## Why

Running several Claude Code agents in one checkout means constant branch-switching, stash juggling,
and agents overwriting each other's files. Git worktrees give each agent an **isolated working
directory that shares one `.git`** — no collisions, no re-clone, instant switching. `ws` wraps the
worktree plumbing into a one-word command and wires up the editor + agent so a new parallel task is a
single line.

---

## Concepts

| Piece | What it is |
|---|---|
| **Worktree** | A second (third, …) working directory for the same repo, checked out to its own branch. `git worktree add`. All worktrees share the repo's object store and refs. |
| **Workspace** | `ws`'s name for a worktree it manages. Lives at `$WS_HOME/<repo>/<name>` (default `~/worktrees/<repo>/<name>`). The `<name>` is the branch, the folder, and the IntelliJ project title. |
| **Seed files** | Gitignored local files (`.env`, etc.) that a fresh checkout lacks. `ws` copies them in so the app runs immediately. |
| **The marker** | A one-shot `.ws-autoclaude` file `ws` drops in the worktree. A shell-startup hook in your rc file sees it, deletes it, and launches `claude`. This is how Claude auto-starts in the workspace's terminal. |
| **Docker isolation** (`-d`) | An optional generated `compose.override.yml` that renames containers + offsets host ports so multiple stacks run at once. |

---

## Commands

| Command | Does |
|---|---|
| `ws -n <name> [base]` | Create branch `<name>` + worktree, seed local files, open in IntelliJ, start a fresh Claude. `base` = ref to branch from (default: current `HEAD`). If `<name>` matches an existing local/remote branch, it checks that out instead of creating one. |
| `ws -r [name]` | Resume a workspace. No name → numbered picker. Claude opens with `--continue` (resumes the last session in that folder). |
| `ws` | Same as `ws -r`. |
| `ws -l` | `git worktree list` for the current repo. |
| `ws -rm [name]` | Remove the worktree (picker if no name). **Keeps the branch** — delete it yourself with `git branch -D <name>`. |
| `ws -d [name] [slot]` | Turn on Docker isolation (see below). `slot` 1–5 sets the port offset; omit to auto-pick from the name. `ws -d <name> off` removes it. |
| `ws -h` | Help. |

---

## How it works (internals)

Everything lives in **one config dir** — `~/.config/ws/` — plus **one block in your shell rc file**.
No per-repo files, no daemon.

### 1. Repo + workspace resolution
`ws` finds the repo by asking git, not by guessing paths:
```
git worktree list --porcelain | first "worktree " line   -> main checkout path
basename of that                                          -> <repo>
$WS_HOME/<repo>/<name>                                    -> workspace dir
```
Because it uses `git worktree list`, it works identically whether you run `ws` from the main checkout
or from inside another worktree.

### 2. Creating the worktree (`-n`)
Picks the right `git worktree add` form:
- existing **local** branch → `git worktree add <dir> <name>`
- existing **remote** branch → `git worktree add --track -b <name> <dir> origin/<name>`
- otherwise → `git worktree add -b <name> <dir> [base]` (new branch off `base`/`HEAD`)

### 3. Seeding local files
A fresh worktree has no gitignored files. `ws` copies `WS_COPY` (default `.env`) from the checkout you
ran it in, plus anything listed in `~/.config/ws/seed/<repo>.txt` (one relative path per line, nested
paths ok). Missing sources are skipped; existing destinations are never overwritten.

### 4. The marker + shell hook (how Claude auto-starts)
`ws` writes a one-shot `.ws-autoclaude` file into the worktree containing the args to pass Claude
(`""` for a fresh session, `--continue` for resume). Your rc file has a startup hook:

```zsh
# zsh (macOS)
if [[ -o interactive && -f "$PWD/.ws-autoclaude" && -z "$WS_CLAUDE_STARTED" ]]; then
  export WS_CLAUDE_STARTED=1
  _ws_claude_args="$(< "$PWD/.ws-autoclaude")"
  command rm -f "$PWD/.ws-autoclaude"          # one-shot: only the first terminal auto-runs
  command -v claude >/dev/null && claude ${=_ws_claude_args}
fi
```

When IntelliJ opens the project and you (or the automation) open its terminal, the shell starts **in
the worktree root**, the hook fires, deletes the marker, and runs Claude. Because it deletes the
marker, only the *first* terminal auto-launches — later terminals in the same folder are plain shells.
`ws -r` re-creates the marker, so resuming re-arms it.

The marker is added to your **global gitignore** so it never shows in `git status`.

### 5. Opening in IntelliJ
`ws` runs `idea <dir>` (the JetBrains Toolbox CLI launcher). On **macOS** it then runs a small
AppleScript (`idea_open.applescript`) that:
1. waits for the new project window,
2. clicks **Window ▸ Merge All Project Windows** (so every repo becomes a tab in one window),
3. raises your workspace's tab,
4. presses **⌥F12** to open the Terminal tool window — which triggers the marker hook above.

This AppleScript needs macOS **Accessibility + Automation** permission (see Troubleshooting). If it
fails or you disable it (`WS_NO_UI=1`), `ws` still opens the project; you just press ⌥F12 yourself and
Claude starts from the marker.

On **Windows** there is no window-merge / AppleScript equivalent, so `ws` just launches `idea <dir>`.
You press **Alt+F12** for the terminal and the `$PROFILE` hook auto-starts Claude. (Simpler — no OS
permission prompts.)

### 6. Docker isolation (`-d`) — optional
Many `compose.yml` files pin `container_name:` and hardcode host ports, so a second `docker compose up`
collides. `ws -d` generates a gitignored **`compose.override.yml`** next to the base file that Compose
auto-merges:
- top-level `name: <repo>-<workspace>` → separate project (network/volumes),
- each service gets `container_name: <svc>-<workspace>`,
- each published port is offset by `slot × 10000` using the Compose **`!override`** tag, so the base
  ports are *replaced*, not appended (a plain override would bind both and still collide).

`gen_override.py` (Python + PyYAML) reads the real compose file to produce this, so it adapts to
whatever services/ports a repo defines. The override filename is added to the repo's local
`.git/info/exclude` so it never dirties `git status`. Requires Docker Compose ≥ 2.24 (for `!override`).

> Note: this **touches no tracked repo files** — only a generated, gitignored override. You don't need
> Docker isolation just to switch between workspaces one at a time: each worktree already has its own
> `./__data` bind-mount, so stopping one stack and starting another is clean on its own.

---

## Repo layout

```
common/gen_override.py        # Docker override generator (cross-platform Python)
macos/
  ws.zsh                      # the command (zsh functions)
  idea_open.applescript       # IntelliJ merge + open-terminal automation
  zshrc-snippet.zsh           # the block appended to ~/.zshrc (source + marker hook)
  install.sh                  # idempotent installer
windows/
  ws.ps1                      # the command (PowerShell port)
  profile-snippet.ps1         # the block appended to $PROFILE (dot-source + marker hook)
  install.ps1                 # idempotent installer
```

The **installed** layout is flat: `install.*` copy `ws.*`, `idea_open.applescript` (mac), and
`gen_override.py` into `~/.config/ws/`, and append the snippet to your rc file.

---

## Install — macOS

Requirements: `git`, `zsh`, [Claude Code](https://claude.com/claude-code) (`claude` on PATH),
IntelliJ IDEA + the JetBrains Toolbox `idea` launcher on PATH, and (for `-d`) Python 3 with PyYAML.

```
git clone https://github.com/Milllr/ws-workspaces.git && bash ws-workspaces/macos/install.sh
```

Then open a new terminal (or `source ~/.zshrc`) and try `ws -n test-branch`.

**First run** triggers macOS permission prompts for the IntelliJ automation — grant them (see
Troubleshooting) or set `export WS_NO_UI=1` in `~/.zshrc` to skip automation and press ⌥F12 yourself.

## Install — Windows

Requirements: `git`, PowerShell (5.1 or 7), Claude Code (`claude` on PATH), IntelliJ IDEA + the
`idea` launcher on PATH (JetBrains Toolbox ▸ Settings ▸ generate shell scripts), Python + PyYAML for `-d`.

```
git clone https://github.com/Milllr/ws-workspaces.git; powershell -ExecutionPolicy Bypass -File ws-workspaces\windows\install.ps1
```

Open a new PowerShell (or `. $PROFILE`) and try `ws -n test-branch`. Windows has no window-merge, so
you get one IntelliJ window per project (or use IntelliJ's "open in new window"); press **Alt+F12** for
the terminal and Claude auto-starts.

> If your IntelliJ terminal is set to **Git Bash** instead of PowerShell, put the marker hook from
> `macos/zshrc-snippet.zsh` (the `if [ -f "$PWD/.ws-autoclaude" ]` block, in bash syntax) into your
> `~/.bashrc` instead — the rest works the same.

---

## Making it robust to any repo

`ws` is repo-agnostic by design, but these are the knobs for repos that need more:

- **Extra local files to seed.** Default is `.env`. For a repo that also needs, say, a service-account
  JSON and a local settings file, create `~/.config/ws/seed/<repo>.txt`:
  ```
  .env
  config/local.settings.json
  secrets/gcp-sa.json
  ```
  (paths are relative to the repo root; nested folders are created). Or set `WS_COPY=".env foo bar"`
  for a one-off.
- **Different worktree location.** `export WS_HOME=/some/where` (default `~/worktrees`). Layout is
  always `$WS_HOME/<repo>/<name>`, so multiple repos coexist cleanly.
- **Repos without IntelliJ.** `ws` still creates/seeds the worktree; the `idea` step just prints a note
  if the launcher isn't found. Set `WS_NO_UI=1` (mac) / `WS_NO_OPEN=1` (win) to skip opening entirely.
- **Repos without Docker.** `ws -d` detects no compose file and says so; nothing else cares.
- **Non-`main` default branch / branching point.** `ws -n <name> <base>` branches from any ref
  (`ws -n hotfix origin/release`).
- **Branch already exists (local or remote).** `ws -n <name>` checks it out into the worktree instead
  of erroring, so it doubles as "give this existing branch its own workspace."

---

## Configuration reference

| Variable | Default | Meaning |
|---|---|---|
| `WS_HOME` | `~/worktrees` | Base dir; workspaces go in `$WS_HOME/<repo>/<name>`. |
| `WS_COPY` | `.env` | Space-separated gitignored files to seed into a new worktree. |
| `~/.config/ws/seed/<repo>.txt` | — | Per-repo extra seed files (one path per line). |
| `WS_IDEA_WAIT` | `15` | macOS: seconds to wait for the IntelliJ window before giving up. |
| `WS_NO_UI` | unset | macOS: skip the AppleScript automation (still opens `idea`). |
| `WS_NO_MERGE` | unset | macOS: open + terminal, but don't merge windows. |
| `WS_NO_TERMINAL` | unset | macOS: open + merge, but don't auto-open the terminal. |
| `WS_NO_OPEN` | unset | Windows: create the worktree without launching IntelliJ. |

---

## Troubleshooting

**macOS: "IntelliJ automation failed" / nothing merges or opens the terminal.**
The AppleScript needs two *separate* macOS permissions for the app you run `ws` from (Terminal.app, or
**IntelliJ IDEA** if you run `ws` in its built-in terminal):
1. **System Settings ▸ Privacy & Security ▸ Accessibility** → toggle that app ON.
2. **System Settings ▸ Privacy & Security ▸ Automation** → allow that app to control **System Events**
   (this prompt only appears the first time an automation runs; run the diagnostic below to trigger it).
3. **Quit and relaunch that app** — Accessibility only takes effect after a restart.

Diagnostic (run in the same terminal you use for `ws`, errors visible):
```
osascript ~/.config/ws/idea_open.applescript "your-workspace-name" 0 0 4; echo "exit=$?"
```
`exit=0` = permissions are good. Approve any "wants to control System Events" popup that appears.

If you'd rather not deal with it: `export WS_NO_UI=1` — `ws` opens the project and you press ⌥F12; the
marker still auto-starts Claude.

**`idea: command not found`.** Install the JetBrains Toolbox shell scripts (Toolbox ▸ Settings ▸ Tools
▸ generate shell scripts) or IntelliJ ▸ Tools ▸ Create Command-line Launcher. Confirm with `which idea`
(mac) / `Get-Command idea` (win).

**`ws -d` says PyYAML missing.** `pip install pyyaml` in whatever Python is first on your PATH, or run
`ws -d` from a shell whose Python has it.

**Two Docker stacks still collide after `-d`.** Give them different slots: `ws -d a 1`, `ws -d b 2`.
Each slot offsets host ports by `slot × 10000` (slot 1 → `8000→18000`, slot 2 → `28000`, … max 5).
The debug ports (5678/5677) are offset too, so attach your IntelliJ debugger to the offset port.

**Claude didn't auto-start in the terminal.** The marker is one-shot and consumed by the first shell in
the folder. Re-arm it with `ws -r <name>`, or just run `claude` yourself. Confirm the rc-file hook is
present (`grep ws-autoclaude ~/.zshrc` / check `$PROFILE`).

---

## Design decisions & limitations

- **One config dir + one rc block, no repo files.** Nothing about `ws` lives in the repos it manages
  (except the transient, gitignored marker/override). You can delete `ws` entirely and your repos are
  untouched.
- **The marker approach** avoids brittle "type `claude` into the terminal" automation — the shell
  launches Claude itself. The only UI automation left (macOS) is *opening* the terminal window.
- **Window-merge is macOS-only** — it's a native macOS feature IntelliJ exposes; Windows/Linux have no
  equivalent, so those platforms get one window per project (or IntelliJ's own new-window handling).
- **`ws -d` needs Compose ≥ 2.24** for the `!override` tag. Below that, you'd have to edit `compose.yml`
  (which `ws` deliberately never does).
- **Port-offset collisions** across slots are possible but unlikely; slots are capped at 5 to keep
  `8000 + slot×10000` under 65535.

---

## Uninstall

```
rm -rf ~/.config/ws                       # remove the tool
# then delete the "ws —" block from ~/.zshrc (mac) or $PROFILE (win)
# optional: git worktree remove each workspace, then rm -rf ~/worktrees
```
