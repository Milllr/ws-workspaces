# ws.ps1 — per-branch git worktree "workspaces" that open in IntelliJ with Claude.
# Windows / PowerShell port of ws.zsh. Dot-source it from your $PROFILE:
#     . "$HOME\.config\ws\ws.ps1"
#
# Usage (mirrors the macOS version):
#   ws -n <name> [base]   new workspace (branch + worktree), open in IntelliJ
#   ws -r [name]          resume (no name -> picker)
#   ws                    resume picker
#   ws -l                 list worktrees
#   ws -rm [name]         remove workspace (keeps branch)
#   ws -d [name] [slot]   isolate docker stack for concurrent runs (slot 1-5; 'off' to disable)
#   ws -h                 help
#
# What differs from macOS: Windows/IntelliJ has no "Merge All Project Windows"
# and no AppleScript, so ws just launches `idea <path>`. Open the terminal
# yourself (Alt+F12) and the $PROFILE hook auto-runs claude via the marker.
#
# Env knobs: $env:WS_HOME (default ~\worktrees), $env:WS_COPY (default ".env"),
#            $env:WS_NO_OPEN=1 to create without launching IntelliJ.
#            Extra per-repo files to seed: list them in <config>\seed\<repo>.txt

$script:WS_DIR = $PSScriptRoot
if (-not $env:WS_HOME) { $env:WS_HOME = Join-Path $HOME 'worktrees' }
if (-not $env:WS_COPY) { $env:WS_COPY = '.env' }

function _ws-InRepo {
  git rev-parse --git-dir *> $null
  return ($LASTEXITCODE -eq 0)
}

# Name of the main repo (works from the main checkout or any linked worktree).
function _ws-RepoName {
  $line = git worktree list --porcelain 2>$null | Select-String '^worktree ' | Select-Object -First 1
  if (-not $line) { return $null }
  $path = ($line.ToString() -replace '^worktree ', '')
  return (Split-Path $path -Leaf)
}

function _ws-WorkspaceDir($name) {
  return (Join-Path (Join-Path $env:WS_HOME (_ws-RepoName)) $name)
}

function _ws-Seed($dir) {
  $root = git rev-parse --show-toplevel 2>$null
  if (-not $root) { return }
  $files = @($env:WS_COPY -split '\s+' | Where-Object { $_ })
  $seedList = Join-Path $script:WS_DIR ("seed\" + (_ws-RepoName) + ".txt")
  if (Test-Path $seedList) { $files += @(Get-Content $seedList | Where-Object { $_.Trim() }) }
  foreach ($f in $files) {
    $src = Join-Path $root $f
    $dst = Join-Path $dir $f
    if ((Test-Path $src) -and -not (Test-Path $dst)) {
      New-Item -ItemType Directory -Force -Path (Split-Path $dst) *> $null
      Copy-Item -Recurse -Force $src $dst
      Write-Host "ws: seeded $f"
    }
  }
}

# One-shot marker read by the $PROFILE hook to auto-launch claude.
function _ws-Mark($dir, $claudeArgs) {
  Set-Content -Path (Join-Path $dir '.ws-autoclaude') -Value $claudeArgs -NoNewline
}

function _ws-Open($dir, $name) {
  if ($env:WS_NO_OPEN) { Write-Host "ws: created $dir  (WS_NO_OPEN set)"; return }
  $idea = Get-Command idea -ErrorAction SilentlyContinue
  if (-not $idea) { $idea = Get-Command idea64.exe -ErrorAction SilentlyContinue }
  if (-not $idea) { $idea = Get-Command idea.cmd -ErrorAction SilentlyContinue }
  Write-Host "ws: $name -> $dir"
  if ($idea) {
    & $idea.Source $dir
    Write-Host "ws: opened in IntelliJ — press Alt+F12 for the terminal; Claude auto-starts."
  } else {
    Write-Host "ws: IntelliJ 'idea' launcher not on PATH — open the folder manually."
    Write-Host "    (JetBrains Toolbox: Settings -> generate shell scripts; adds 'idea' to PATH.)"
  }
}

function _ws-Names {
  $base = Join-Path $env:WS_HOME (_ws-RepoName)
  if (-not (Test-Path $base)) { return @() }
  return @(Get-ChildItem -Directory $base | Select-Object -ExpandProperty Name)
}

function _ws-Pick {
  $names = _ws-Names
  if ($names.Count -eq 0) {
    Write-Host "ws: no workspaces for '$(_ws-RepoName)' — create one: ws -n <name>"
    return $null
  }
  Write-Host "workspaces for $(_ws-RepoName):"
  for ($i = 0; $i -lt $names.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $names[$i]) }
  $choice = Read-Host "select [1-$($names.Count)]"
  if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $names.Count) {
    return $names[[int]$choice - 1]
  }
  Write-Host "ws: cancelled"
  return $null
}

function _ws-New([string[]]$a) {
  $name = $a[0]; $base = $a[1]
  if (-not $name) { Write-Host "usage: ws -n <name> [base-ref]"; return }
  if (-not (_ws-InRepo)) { Write-Host "ws: not inside a git repo"; return }
  $dir = _ws-WorkspaceDir $name
  if (Test-Path $dir) { Write-Host "ws: workspace exists: $dir  (resume: ws -r $name)"; return }
  New-Item -ItemType Directory -Force -Path (Split-Path $dir) *> $null
  git show-ref --verify --quiet "refs/heads/$name"
  if ($LASTEXITCODE -eq 0) {
    git worktree add $dir $name
  } else {
    git ls-remote --exit-code --heads origin $name *> $null
    if ($LASTEXITCODE -eq 0) {
      git worktree add --track -b $name $dir "origin/$name"
    } elseif ($base) {
      git worktree add -b $name $dir $base
    } else {
      git worktree add -b $name $dir
    }
  }
  if ($LASTEXITCODE -ne 0) { return }
  _ws-Seed $dir
  _ws-Mark $dir ''
  _ws-Open $dir $name
}

function _ws-Resume([string[]]$a) {
  if (-not (_ws-InRepo)) { Write-Host "ws: not inside a git repo"; return }
  $name = $a[0]
  if (-not $name) { $name = _ws-Pick; if (-not $name) { return } }
  $dir = _ws-WorkspaceDir $name
  if (-not (Test-Path $dir)) { Write-Host "ws: no such workspace: $name"; return }
  _ws-Mark $dir '--continue'
  _ws-Open $dir $name
}

function _ws-List {
  if (-not (_ws-InRepo)) { Write-Host "ws: not inside a git repo"; return }
  Write-Host "worktrees for $(_ws-RepoName):"
  git worktree list
}

function _ws-Remove([string[]]$a) {
  if (-not (_ws-InRepo)) { Write-Host "ws: not inside a git repo"; return }
  $name = $a[0]
  if (-not $name) { $name = _ws-Pick; if (-not $name) { return } }
  $dir = _ws-WorkspaceDir $name
  if (-not (Test-Path $dir)) { Write-Host "ws: no such workspace: $name"; return }
  git worktree remove $dir 2>$null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "ws: worktree busy or has changes. Force with: git worktree remove --force `"$dir`""
    return
  }
  git worktree prune
  Write-Host "ws: removed workspace '$name'. Branch kept — delete with: git branch -D $name"
}

function _ws-Docker([string[]]$a) {
  if (-not (_ws-InRepo)) { Write-Host "ws: not inside a git repo"; return }
  $name = $a[0]
  $slot = if ($a[1]) { $a[1] } else { '0' }
  $off = $false
  if ($a[0] -eq 'off') { $off = $true; $name = $a[1] }
  if ($a[1] -eq 'off') { $off = $true }
  if (-not $name) { $name = _ws-Pick; if (-not $name) { return } }
  if ($slot -notmatch '^\d+$') { $slot = '0' }
  $repo = _ws-RepoName
  $dir = _ws-WorkspaceDir $name
  if (-not (Test-Path $dir)) { Write-Host "ws: no such workspace: $name"; return }

  $base = $null
  foreach ($f in 'compose.yaml', 'compose.yml', 'docker-compose.yaml', 'docker-compose.yml') {
    if (Test-Path (Join-Path $dir $f)) { $base = $f; break }
  }
  if (-not $base) { Write-Host "ws: no compose file in $dir — nothing to isolate"; return }
  $override = [IO.Path]::GetFileNameWithoutExtension($base) + '.override' + [IO.Path]::GetExtension($base)

  if ($off) {
    Remove-Item -Force (Join-Path $dir $override) -ErrorAction SilentlyContinue
    Write-Host "ws: docker isolation OFF for '$name' (removed $override)"
    return
  }

  $py = Get-Command python -ErrorAction SilentlyContinue
  if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
  if (-not $py) { Write-Host "ws: python not found (needed for ws -d)"; return }

  $out = & $py.Source (Join-Path $script:WS_DIR 'gen_override.py') (Join-Path $dir $base) $name $slot $repo
  if ($LASTEXITCODE -ne 0) { return }

  # Keep the generated override out of `git status` (repo-local, not committed).
  $common = git rev-parse --path-format=absolute --git-common-dir 2>$null
  if ($common) {
    $excl = Join-Path $common 'info\exclude'
    if ((Test-Path $excl) -and -not (Select-String -Quiet -SimpleMatch $override $excl)) {
      Add-Content $excl $override
    }
  }

  $lines = @($out)
  Write-Host "ws: docker isolation ON for '$name'  (project: $($lines[1]))"
  $lines | Select-Object -Skip 2 | ForEach-Object { if ($_ -match '^port ') { Write-Host ("  " + ($_ -replace '^port ', '')) } }
  Write-Host "  run:     cd `"$dir`"; make run   (auto-merges $override)"
  Write-Host "  disable: ws -d $name off"
}

function _ws-Help {
  Write-Host @"
ws — per-branch worktree workspaces (open in IntelliJ + Claude)
  ws -n <name> [base]   new workspace (branch + worktree), open it
  ws -r [name]          resume (no name -> picker)
  ws                    resume picker
  ws -l                 list worktrees
  ws -rm [name]         remove workspace (keeps branch)
  ws -d [name] [slot]   isolate docker stack for concurrent runs (slot 1-5; 'off' to disable)
  ws -h                 this help
worktrees live under: $env:WS_HOME\<repo>\<name>
"@
}

function ws {
  $a = @($args)
  $cmd = if ($a.Count -ge 1) { $a[0] } else { '' }
  $rest = if ($a.Count -gt 1) { $a[1..($a.Count - 1)] } else { @() }
  switch -Regex ($cmd) {
    '^(-n|--new)$'     { _ws-New $rest; break }
    '^(-r|--resume)$'  { _ws-Resume $rest; break }
    '^(-l|--list)$'    { _ws-List; break }
    '^(-rm|--remove)$' { _ws-Remove $rest; break }
    '^(-d|--docker)$'  { _ws-Docker $rest; break }
    '^(-h|--help)$'    { _ws-Help; break }
    '^$'               { _ws-Resume @(); break }
    default            { Write-Host "ws: unknown '$cmd' (new workspace? ws -n `"$cmd`")" }
  }
}
