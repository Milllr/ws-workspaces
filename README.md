<a href="https://mllr.ca/media/ws-music.mp4"><img src=".github/readme/ws.gif" width="100%" alt="ws in a terminal: one command opens the same branch in three repos, and a Claude session starts working in each one"></a>

# ws

work on many tickets on the same repo concurrently

<img src=".github/readme/ws.svg" width="100%" alt="One main line forks into three worktrees, each with its own Claude session, and they merge back into main">

## Install

macOS, Linux, Git Bash or WSL

```
git clone https://github.com/Milllr/ws-workspaces.git && bash ws-workspaces/install/install.sh
```

Windows PowerShell

```
git clone https://github.com/Milllr/ws-workspaces.git; powershell -ExecutionPolicy Bypass -File ws-workspaces\install\install.ps1
```

Open a new terminal and you're set.

```
ws -n my-branch
```

[the full reel](https://mllr.ca/media/ws-music.mp4) · [every command](docs/MANUAL.md)
