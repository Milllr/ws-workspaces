# ws — per-branch workspaces for parallel Claude Code sessions

`ws` is a small, universal command for working on **many branches of one repo at the same time** —
each in its own directory, its own editor project, and its own Claude Code session, with zero branch
switching, stashing, or agents clobbering each other.

```
ws -n "bug-1203-blank-image"          # new branch+worktree, opens in your editor, Claude auto-starts
ws -n hotfix -- "revert the bad migration and add a test"   # ...and hand Claude a starting task
ws                                     # fuzzy/menu picker → resume a workspace (Claude --continue)
ws cd bug-1203                          # jump this shell into a workspace
ws -l                                  # dashboard: branch · dirty? · ahead/behind · docker · age
ws -rm bug-1203 -b                      # tear down (‑b also deletes the branch)
ws -d  bug-1203                         # (optional) isolate its Docker stack to run concurrently
ws doctor                              # check your environment
```

Built on **git worktrees** plus a thin layer that seeds local config, opens the folder in your editor,
and auto-launches Claude. Runs on **macOS, Linux, Git Bash, and WSL** (one bash core) and **native
Windows PowerShell** (a parallel port). Touches no files in the repos it manages.

---

## Why

Running several Claude agents in one checkout means constant branch-switching, stash juggling, and
agents overwriting each other. Git worktrees give each agent an **isolated working directory that
shares one `.git`** — no collisions, no re-clone, instant switching. `ws` turns that into one word and
wires up the editor + agent so spinning up a parallel task is a single line.

---

## Install

**macOS / Linux / Git Bash / WSL**
```
git clone https://github.com/Milllr/ws-workspaces.git && bash ws-workspaces/install/install.sh
```

**Windows (PowerShell)**
```
git clone https://github.com/Milllr/ws-workspaces.git; powershell -ExecutionPolicy Bypass -File ws-workspaces\install\install.ps1
```

Then open a new terminal (or re-source your rc) and run `ws doctor`. The installer is idempotent —
re-run it to upgrade. It:
- copies the tool to `~/.config/ws/` and symlinks `~/.local/bin/ws` (Unix),
- adds a replaceable `# >>> ws >>>` block to `~/.zshrc` / `~/.bashrc` / `$PROFILE`,
- adds `.ws-autoclaude` to your global gitignore,
- creates `~/worktrees/`.

**Requirements:** `git`, Claude Code (`claude` on PATH), an editor launcher (IntelliJ's `idea`, or
`code`/`cursor`) — optional, and Python 3 + PyYAML + Docker Compose ≥ 2.24 **only if** you use `ws -d`.
`ws doctor` tells you exactly what's present.

---

## Commands

| Command | Does |
|---|---|
| `ws -n <name> [base] [-- <prompt>]` | Create branch `<name>` + worktree, seed local files, open in editor, start Claude. `base` = ref to branch from (default `HEAD`). `-- <prompt>` (or `-p "<prompt>"`) hands Claude a starting task. If `<name>` is an existing local/remote branch, it's checked out instead of created. |
| `ws` / `ws -r [name]` | Resume. No name → picker (fzf if installed, else numbered menu). Claude opens with `--continue`. |
| `ws cd [name]` | `cd` the current shell into a workspace (needs the shell hook; installed by default). |
| `ws -l` / `ws ls` / `ws status` | Dashboard: each workspace's branch, clean/dirty, ahead/behind upstream, docker-isolated?, last-commit age. |
| `ws -rm [name] [-f] [-b]` | Remove the worktree. Warns on uncommitted/unpushed work; `-f` forces, `-b` also deletes the branch. |
| `ws seed [name]` | Re-copy seed files into an existing workspace (e.g. after `.env` changed). |
| `ws -d [name] [slot\|off]` | Toggle Docker isolation (see below). `slot` 1–5 sets the port offset. |
| `ws doctor` | Check git/claude/editor/python/PyYAML/docker/fzf and (macOS) Accessibility. |
| `ws version` · `ws -h` | Version · help. |

Word forms and flags are interchangeable: `new`/`-n`, `resume`/`switch`/`-r`, `ls`/`list`/`status`/`-l`,
`rm`/`remove`/`-rm`, `docker`/`-d`. Tab-completion covers subcommands and workspace names.

---

## Claude efficiency

The pieces that make parallel agents actually fast to run:

- **Permissions carry over.** `ws` seeds `.claude/settings.local.json` (your approved tool
  permissions, normally gitignored) into every new worktree — so Claude doesn't re-prompt for
  permission in each workspace. This is on by default via `WS_COPY`.
- **Auto-start.** A one-shot `.ws-autoclaude` marker + a shell hook launch Claude the moment the
  workspace's terminal opens — no typing `claude` each time.
- **Resume in place.** `ws -r` starts Claude with `--continue`, so you drop straight back into that
  workspace's last session.
- **Kick off with a task.** `ws -n <name> -- "<prompt>"` starts the agent already working on something.
- **Instant switching.** `ws` (fuzzy picker), `ws cd <name>`, and `ws -l` make hopping between
  concurrent agents a keystroke or two.

---

## How it works (internals)

Everything lives in **one config dir** (`~/.config/ws/`) plus **one block in your shell rc**. No
per-repo files, no daemon.

1. **Resolution.** The repo is found via `git worktree list` (not path guessing), so `ws` behaves the
   same from the main checkout or any worktree. Workspaces live at `$WS_HOME/<repo>/<name>` (default
   `~/worktrees/<repo>/<name>`); `<name>` is the branch, the folder, and the editor project title.
2. **Create.** Picks the right `git worktree add` form (new branch / existing local / tracked remote).
3. **Seed.** Copies `WS_COPY` (default `.env` + `.claude/settings.local.json`) plus anything in
   `~/.config/ws/seed/<repo>.txt` from the checkout you ran `ws` in. Nested paths handled; existing
   files never overwritten.
4. **Marker + hook.** `ws` writes `.ws-autoclaude` (line 1 = mode `fresh`/`continue`/`prompt`, rest =
   prompt). The rc hook, on the first interactive shell that starts in the folder, reads it, deletes it
   (one-shot), and runs `claude` / `claude --continue` / `claude "<prompt>"`. The marker is globally
   gitignored.
5. **Open.** Launches the resolved editor (`WS_EDITOR`). On **macOS + IntelliJ** it also runs a small
   AppleScript to *Merge All Project Windows* (so every repo is a tab in one window) and open the
   Terminal tool window (⌥F12) — which triggers the hook. Elsewhere it just opens the folder and you
   open the terminal yourself (IntelliJ on Windows: Alt+F12); the hook still starts Claude.
6. **Docker isolation (`-d`, optional).** Generates a gitignored `compose.override.yml` that Compose
   auto-merges: a per-workspace project `name:`, `container_name: <svc>-<workspace>`, and every host
   port offset by `slot × 10000` via the Compose **`!override`** tag (so base ports are *replaced*, not
   doubled). `gen_override.py` reads the real compose file, so it adapts to any services/ports. The
   override name is added to the repo's local `.git/info/exclude`. Needs Compose ≥ 2.24.

> `ws -d` touches **no tracked repo files**. You don't need it just to switch stacks one at a time —
> each worktree already has its own `./__data`, so stopping one and starting another is clean.

---

## Cross-system notes

| | macOS | Linux / Git Bash / WSL | Windows PowerShell |
|---|---|---|---|
| Core | `bin/ws` (bash) | `bin/ws` (bash) | `bin/ws.ps1` |
| Editor open | IntelliJ w/ window-merge + auto-terminal (AppleScript) | opens editor; you open the terminal | opens editor (Alt+F12 for terminal) |
| `ws cd` | ✓ (shell fn) | ✓ (shell fn) | ✓ (`Set-Location`) |
| Everything else | ✓ | ✓ | ✓ |

The macOS window-merge/auto-terminal is a native-macOS feature with no Windows/Linux equivalent, so
those platforms get one window per project and rely on the marker hook to start Claude. Simpler, and
no OS permission prompts.

> Git Bash / WSL on Windows: the bash core works, but it launches the *Windows* `idea`. If you run
> your IntelliJ terminal as Git Bash, the bash hook applies; if PowerShell, use the PowerShell install.

---

## Configuration

Set via env vars, `~/.config/ws/config` (a sourced shell file; copy `config.example`), or per-repo
files. Precedence: env > config > defaults.

| Variable | Default | Meaning |
|---|---|---|
| `WS_HOME` | `~/worktrees` | Base dir; `$WS_HOME/<repo>/<name>`. |
| `WS_COPY` | `.env .claude/settings.local.json` | Space-separated gitignored files to seed. |
| `~/.config/ws/seed/<repo>.txt` | — | Per-repo extra seed files, one path per line. |
| `WS_EDITOR` | `auto` | `auto` (idea→code→cursor) / `idea` / `code` / `cursor` / `none` / any command. |
| `WS_IDEA_WAIT` | `15` | macOS: seconds to wait for the IntelliJ window. |
| `WS_NO_UI` | unset | macOS: skip the AppleScript (still opens the editor). |
| `WS_NO_MERGE` / `WS_NO_TERMINAL` | unset | macOS: skip just the window-merge / terminal step. |

**Any repo works out of the box** — a repo with no `.env` just skips it, a repo with no compose file
makes `ws -d` a no-op, a repo you don't open in an editor still gets its worktree (`WS_EDITOR=none`,
then `ws cd`). Add per-repo seed files for anything else a fresh checkout needs.

---

## Repo layout

```
bin/ws              # bash core (macOS/Linux/Git-Bash/WSL)
bin/ws.ps1          # PowerShell core (native Windows)
common/gen_override.py   # Docker override generator (shared)
lib/idea_open.applescript # macOS IntelliJ merge + open-terminal
shell/hook.zsh · hook.bash · hook.ps1   # rc integration (ws fn, marker hook, completion)
install/install.sh · install.ps1        # idempotent installers
config.example
```
Installed layout is flat under `~/.config/ws/`.

---

## Troubleshooting

Run **`ws doctor`** first — it flags anything missing.

**macOS: "IntelliJ automation failed".** The AppleScript needs two macOS permissions for the app you
run `ws` from (Terminal.app, or **IntelliJ IDEA** if you use its built-in terminal):
1. System Settings ▸ Privacy & Security ▸ **Accessibility** → toggle that app ON.
2. System Settings ▸ Privacy & Security ▸ **Automation** → allow it to control **System Events**.
3. **Quit and relaunch** that app (Accessibility only applies after a restart).

Diagnostic (run in the terminal you use for `ws`): `osascript ~/.config/ws/idea_open.applescript "any-name" 0 0 4; echo exit=$?`
— `exit=0` means good; approve any "control System Events" popup. Or set `WS_EDITOR=idea` + `WS_NO_UI=1`
and press ⌥F12 yourself (the hook still starts Claude).

**`idea`/`code`/`cursor` not found.** Install the editor's CLI launcher (JetBrains Toolbox ▸ Settings ▸
generate shell scripts; VS Code ▸ "Shell Command: Install 'code' command"). Or set `WS_EDITOR=none`.

**`ws -d` needs PyYAML / Compose ≥ 2.24.** `pip install pyyaml`; check `docker compose version`.

**Two stacks still collide after `-d`.** Use different slots: `ws -d a 1`, `ws -d b 2` (offset = slot ×
10000). Debug ports are offset too — attach the debugger to the offset port.

**Claude didn't auto-start.** The marker is one-shot; re-arm with `ws -r <name>` or just run `claude`.
Confirm the rc hook is present (the `# >>> ws >>>` block).

---

## Uninstall

```
rm -rf ~/.config/ws ~/.local/bin/ws          # remove the tool
# delete the "# >>> ws >>>" block from ~/.zshrc / ~/.bashrc / $PROFILE
# optional: remove worktrees with `ws -rm`, then rm -rf ~/worktrees
```

MIT licensed. Built for driving many Claude Code agents in parallel without stepping on yourself.
