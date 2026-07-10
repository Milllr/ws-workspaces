# ws.ps1 — per-branch git worktree "workspaces" for parallel Claude Code sessions.
# Windows / PowerShell port (5.1 and 7 compatible). Dot-sourced from $PROFILE via
# shell/hook.ps1, which also adds the marker auto-start and tab-completion.
#
# What differs from macOS: no "Merge All Project Windows" / AppleScript. ws just
# launches `idea <path>`; you press Alt+F12 for the terminal and Claude auto-starts.

$script:WS_VERSION = '2.0.0'
$script:WS_DIR = $PSScriptRoot

# ---- config + defaults ------------------------------------------------------
$__cfg = Join-Path $script:WS_DIR 'config.ps1'
if (Test-Path $__cfg) { . $__cfg }
if (-not $env:WS_HOME)   { $env:WS_HOME   = Join-Path $HOME 'worktrees' }
# .claude/settings.local.json carries approved Claude permissions into each workspace.
if (-not $env:WS_COPY)   { $env:WS_COPY   = '.env .claude/settings.local.json' }
if (-not $env:WS_EDITOR) { $env:WS_EDITOR = 'auto' }

# ---- helpers ----------------------------------------------------------------
function _ws-Say($m) { Write-Host "ws: $m" }
function _ws-Err($m) { Write-Host "ws: $m" -ForegroundColor Yellow }

function _ws-InRepo {
  git rev-parse --git-dir *> $null
  return ($LASTEXITCODE -eq 0)
}
function _ws-MainPath {
  $line = git worktree list --porcelain 2>$null | Select-String '^worktree ' | Select-Object -First 1
  if ($line) { return ($line.ToString() -replace '^worktree ', '') }
}
function _ws-RepoName {
  $m = _ws-MainPath
  if ($m) { return (Split-Path $m -Leaf) }
}
function _ws-Base { Join-Path $env:WS_HOME (_ws-RepoName) }
function _ws-Dir($name) { Join-Path (_ws-Base) $name }

# Where sibling repos live (for -a): $env:WS_CODE_ROOT (';'-separated) or the
# parent of the current repo's main checkout.
function _ws-CodeRoots {
  if ($env:WS_CODE_ROOT) { return @($env:WS_CODE_ROOT -split ';' | Where-Object { $_ }) }
  return @(Split-Path (_ws-MainPath) -Parent)
}
function _ws-ResolveRepo($nm) {
  if ($nm -match '[\\/]' -or $nm.StartsWith('~') -or $nm.StartsWith('.')) {
    $cand = $nm -replace '^~', $HOME
    $tl = git -C $cand rev-parse --show-toplevel 2>$null
    if ($tl) { return $tl } else { return $null }
  }
  foreach ($root in (_ws-CodeRoots)) {
    $p = Join-Path $root $nm
    git -C $p rev-parse --git-dir *> $null
    if ($LASTEXITCODE -eq 0) { return $p }
  }
  return $null
}

function _ws-ValidName($name) {
  if (-not $name) { return $false }
  if ($name -match '[\\/ ]' -or $name.StartsWith('.')) { return $false }
  return $true
}

function _ws-Names {
  if (-not (_ws-InRepo)) { return @() }
  $base = _ws-Base
  if (-not (Test-Path $base)) { return @() }
  return @(Get-ChildItem -Directory $base -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
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
      _ws-Say "seeded $f"
    }
  }
}

function _ws-Mark($dir, $mode, $payload) {
  $content = "$mode`n"
  if ($payload) { $content += $payload }
  [IO.File]::WriteAllText((Join-Path $dir '.ws-autoclaude'), $content)
}

function _ws-ResolveEditor {
  switch ($env:WS_EDITOR) {
    'none' { return 'none' }
    'auto' {
      foreach ($e in 'idea', 'code', 'cursor') {
        if (Get-Command $e -ErrorAction SilentlyContinue) { return $e }
      }
      return 'none'
    }
    default { return $env:WS_EDITOR }
  }
}

function _ws-Open($dir, $name) {
  $ed = _ws-ResolveEditor
  _ws-Say "$name -> $dir"
  if ($ed -eq 'none') { _ws-Say "no editor set. Enter it with: ws cd $name  (then: claude)"; return }
  $cmd = Get-Command $ed -ErrorAction SilentlyContinue
  if (-not $cmd) { _ws-Say "editor '$ed' not on PATH — open $dir manually, then run: claude"; return }
  & $cmd.Source $dir
  _ws-Say "opened in $ed — open its terminal (IntelliJ: Alt+F12) and Claude auto-starts."
}

function _ws-Pick {
  $names = _ws-Names
  if ($names.Count -eq 0) { _ws-Err "no workspaces for '$(_ws-RepoName)' — create one: ws -n <name>"; return $null }
  if (Get-Command fzf -ErrorAction SilentlyContinue) {
    $sel = $names | fzf --prompt="ws> " --height=40% --reverse --no-multi
    if ($sel) { return $sel } else { return $null }
  }
  Write-Host "workspaces for $(_ws-RepoName):"
  for ($i = 0; $i -lt $names.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $names[$i]) }
  $choice = Read-Host "select [1-$($names.Count)]"
  if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $names.Count) {
    return $names[[int]$choice - 1]
  }
  _ws-Err "cancelled"; return $null
}
function _ws-ResolveName($name) {
  if (-not $name) { $name = _ws-Pick; if (-not $name) { return $null } }
  return $name
}

# ---- commands ---------------------------------------------------------------
# --- per-repo primitives (assume the current location is inside the repo) ----
function _ws-DoNewOne($name, $base, $prompt) {
  $dir = _ws-Dir $name
  if (Test-Path $dir) { _ws-Err "[$(_ws-RepoName)] workspace exists: $dir"; return }
  New-Item -ItemType Directory -Force -Path (_ws-Base) *> $null
  git show-ref --verify --quiet "refs/heads/$name"
  if ($LASTEXITCODE -eq 0) {
    git worktree add $dir $name
  } else {
    git ls-remote --exit-code --heads origin $name *> $null
    if ($LASTEXITCODE -eq 0) { git worktree add --track -b $name $dir "origin/$name" }
    elseif ($base) { git worktree add -b $name $dir $base }
    else { git worktree add -b $name $dir }
  }
  if ($LASTEXITCODE -ne 0) { return }
  _ws-Seed $dir
  if ($prompt) { _ws-Mark $dir 'prompt' $prompt } else { _ws-Mark $dir '' '' }
  _ws-Open $dir $name
}
function _ws-DoResumeOne($name) {
  $dir = _ws-Dir $name
  if (-not (Test-Path $dir)) { _ws-Err "[$(_ws-RepoName)] no such workspace: $name"; return }
  _ws-Mark $dir 'continue' ''
  _ws-Open $dir $name
}
function _ws-DoEnsureOne($name, $base, $prompt) {
  $dir = _ws-Dir $name
  if (Test-Path $dir) { _ws-DoResumeOne $name } else { _ws-DoNewOne $name $base $prompt }
}
function _ws-RunAcross($name, $prompt, $repos) {
  foreach ($r in $repos) {
    $path = _ws-ResolveRepo $r
    if (-not $path) { _ws-Err "── skip '$r': no such repo under $((_ws-CodeRoots) -join ';') (set WS_CODE_ROOT?)"; continue }
    _ws-Say "── also: $(Split-Path $path -Leaf) ──"
    Push-Location $path
    try { _ws-DoEnsureOne $name '' $prompt } finally { Pop-Location }
  }
}
function _ws-RunAcrossSplit($name, $prompt, $repos) {
  if (-not $repos -or $repos.Count -eq 0) { return }
  $flat = @()
  foreach ($x in $repos) { $flat += ($x -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
  if ($flat.Count) { _ws-RunAcross $name $prompt $flat }
}

function _ws-New([string[]]$a) {
  $name = ''; $base = ''; $prompt = ''; $repos = @(); $state = 'pos'
  $i = 0
  while ($i -lt $a.Count) {
    $t = $a[$i]
    if ($t -match '^(-a|--also)$') { $state = 'repos' }
    elseif ($t -match '^(-p|--prompt)$') { $i++; $prompt = $a[$i]; $state = 'pos' }
    elseif ($t -eq '--') { $i++; if ($i -lt $a.Count) { $prompt = ($a[$i..($a.Count - 1)] -join ' ') }; break }
    elseif ($t -like '-*') { _ws-Err "ignoring unknown flag: $t" }
    else {
      if ($state -eq 'repos') { $repos += $t }
      elseif (-not $name) { $name = $t } elseif (-not $base) { $base = $t }
    }
    $i++
  }
  if (-not $name) { _ws-Err "usage: ws new <name> [base] [-a repo,repo] [-- <prompt>]"; return }
  if (-not (_ws-ValidName $name)) { _ws-Err "invalid name '$name' (no spaces, slashes, or leading dot)"; return }
  if (-not (_ws-InRepo)) { _ws-Err "not inside a git repo"; return }
  _ws-DoNewOne $name $base $prompt
  _ws-RunAcrossSplit $name $prompt $repos
}

# `ws -a <repo>[,repo...]` — set up the SAME-named workspace (= current branch)
# in the other repo(s) too.
function _ws-Also([string[]]$a) {
  if (-not (_ws-InRepo)) { _ws-Err "not inside a git repo"; return }
  if (-not $a -or $a.Count -eq 0) { _ws-Err "usage: ws -a <repo>[,repo...]"; return }
  $name = git rev-parse --abbrev-ref HEAD 2>$null
  if (-not $name -or $name -eq 'HEAD') { _ws-Err "can't determine current branch"; return }
  _ws-Say "using workspace name '$name' (current branch)"
  _ws-RunAcrossSplit $name '' $a
}

function _ws-Resume([string[]]$a) {
  if (-not (_ws-InRepo)) { _ws-Err "not inside a git repo"; return }
  $name = ''; $repos = @(); $state = 'pos'
  foreach ($t in $a) {
    if ($t -match '^(-a|--also)$') { $state = 'repos' }
    elseif ($t -like '-*') { _ws-Err "ignoring unknown flag: $t" }
    else { if ($state -eq 'repos') { $repos += $t } elseif (-not $name) { $name = $t } }
  }
  $name = _ws-ResolveName $name; if (-not $name) { return }
  _ws-DoResumeOne $name
  _ws-RunAcrossSplit $name '' $repos
}

function _ws-Path([string[]]$a) {
  if (-not (_ws-InRepo)) { return }
  $name = _ws-ResolveName $a[0]; if (-not $name) { return }
  $dir = _ws-Dir $name
  if (Test-Path $dir) { return $dir }
}

function _ws-Cd([string[]]$a) {
  $dir = _ws-Path $a
  if ($dir) { Set-Location $dir } else { _ws-Err "no such workspace" }
}

function _ws-List {
  if (-not (_ws-InRepo)) { _ws-Err "not inside a git repo"; return }
  $repo = _ws-RepoName; $base = _ws-Base
  $names = _ws-Names
  if ($names.Count -eq 0) { _ws-Say "no workspaces for '$repo' — create one: ws -n <name>"; return }
  Write-Host "workspaces for $repo  ($base):"
  foreach ($n in $names) {
    $dir = Join-Path $base $n
    $branch = git -C $dir rev-parse --abbrev-ref HEAD 2>$null
    $dirty = if (git -C $dir status --porcelain 2>$null) { '● dirty' } else { '✓ clean' }
    $ab = ''
    $up = git -C $dir rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if ($up) {
      $counts = (git -C $dir rev-list --left-right --count '@{u}...HEAD' 2>$null) -split '\s+'
      if ([int]($counts[1]) -gt 0) { $ab += " ↑$($counts[1])" }
      if ([int]($counts[0]) -gt 0) { $ab += " ↓$($counts[0])" }
    } else { $ab = ' (no upstream)' }
    $dock = if (Get-ChildItem $dir -Filter '*.override.y*ml' -ErrorAction SilentlyContinue) { ' · docker' } else { '' }
    $rel = git -C $dir log -1 --format=%cr 2>$null
    Write-Host ("  {0,-26} {1,-14} {2}{3}{4} · {5}" -f $n, $branch, $dirty, $ab, $dock, $rel)
  }
}

function _ws-Remove([string[]]$a) {
  if (-not (_ws-InRepo)) { _ws-Err "not inside a git repo"; return }
  $force = $false; $delbranch = $false; $name = ''
  foreach ($x in $a) {
    switch -Regex ($x) {
      '^(-f|--force)$'  { $force = $true }
      '^(-b|--branch)$' { $delbranch = $true }
      default { $name = $x }
    }
  }
  $name = _ws-ResolveName $name; if (-not $name) { return }
  $dir = _ws-Dir $name
  if (-not (Test-Path $dir)) { _ws-Err "no such workspace: $name"; return }
  if (-not $force) {
    $issues = @()
    if (git -C $dir status --porcelain 2>$null) { $issues += 'uncommitted changes' }
    $up = git -C $dir rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if ($up) {
      $ahead = git -C $dir rev-list --count '@{u}..HEAD' 2>$null
      if ([int]$ahead -gt 0) { $issues += "$ahead unpushed commit(s)" }
    }
    if ($issues.Count) {
      _ws-Err "workspace '$name' has $($issues -join ', ')."
      $ans = Read-Host "ws: remove anyway? [y/N]"
      if ($ans -notmatch '^(y|Y|yes)$') { _ws-Err "aborted"; return }
    }
  }
  if ($force) { git worktree remove --force $dir } else { git worktree remove $dir }
  if ($LASTEXITCODE -ne 0) { _ws-Err "worktree busy/dirty — retry: ws rm $name --force"; return }
  git worktree prune
  _ws-Say "removed workspace '$name'"
  if ($delbranch) { git branch -D $name *> $null; _ws-Say "deleted branch '$name'" }
  else { _ws-Say "branch '$name' kept — delete with: git branch -D $name" }
}

function _ws-SeedCmd([string[]]$a) {
  if (-not (_ws-InRepo)) { _ws-Err "not inside a git repo"; return }
  $name = _ws-ResolveName $a[0]; if (-not $name) { return }
  $dir = _ws-Dir $name
  if (-not (Test-Path $dir)) { _ws-Err "no such workspace: $name"; return }
  _ws-Seed $dir; _ws-Say "re-seeded $name"
}

function _ws-Docker([string[]]$a) {
  if (-not (_ws-InRepo)) { _ws-Err "not inside a git repo"; return }
  $name = $a[0]; $arg2 = $a[1]; $off = $false; $slot = '0'
  if ($a[0] -eq 'off') { $off = $true; $name = $a[1]; $arg2 = $null }
  if ($a[1] -eq 'off') { $off = $true }
  if ($arg2 -match '^\d+$') { $slot = $arg2 }
  $name = _ws-ResolveName $name; if (-not $name) { return }
  $dir = _ws-Dir $name
  if (-not (Test-Path $dir)) { _ws-Err "no such workspace: $name"; return }
  $base = $null
  foreach ($f in 'compose.yaml', 'compose.yml', 'docker-compose.yaml', 'docker-compose.yml') {
    if (Test-Path (Join-Path $dir $f)) { $base = $f; break }
  }
  if (-not $base) { _ws-Err "no compose file in $dir — nothing to isolate"; return }
  $override = [IO.Path]::GetFileNameWithoutExtension($base) + '.override' + [IO.Path]::GetExtension($base)
  if ($off) {
    Remove-Item -Force (Join-Path $dir $override) -ErrorAction SilentlyContinue
    _ws-Say "docker isolation OFF for '$name' (removed $override)"; return
  }
  $py = Get-Command python -ErrorAction SilentlyContinue
  if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
  if (-not $py) { _ws-Err "python not found (needed for ws -d)"; return }
  $out = & $py.Source (Join-Path $script:WS_DIR 'gen_override.py') (Join-Path $dir $base) $name $slot (_ws-RepoName)
  if ($LASTEXITCODE -ne 0) { return }
  $common = git rev-parse --path-format=absolute --git-common-dir 2>$null
  if ($common) {
    $excl = Join-Path $common 'info\exclude'
    if ((Test-Path $excl) -and -not (Select-String -Quiet -SimpleMatch $override $excl)) { Add-Content $excl $override }
  }
  $lines = @($out)
  _ws-Say "docker isolation ON for '$name'  (project: $($lines[1]))"
  $lines | Select-Object -Skip 2 | ForEach-Object { if ($_ -match '^port ') { Write-Host ("  " + ($_ -replace '^port ', '')) } }
  Write-Host "  run:     cd `"$dir`"; make run   (auto-merges $override)"
  Write-Host "  disable: ws -d $name off"
}

function _ws-Check($label, $ok) { if ($ok) { Write-Host "  [ok] $label" } else { Write-Host "  [--] $label" } }
function _ws-Doctor {
  Write-Host "ws doctor — v$script:WS_VERSION (Windows)"
  Write-Host "  config dir : $script:WS_DIR"
  Write-Host "  worktrees  : $env:WS_HOME"
  Write-Host "  editor     : $env:WS_EDITOR -> $(_ws-ResolveEditor)"
  Write-Host "  seed files : $env:WS_COPY"
  _ws-Check 'git'                    ([bool](Get-Command git -ErrorAction SilentlyContinue))
  _ws-Check 'claude CLI'             ([bool](Get-Command claude -ErrorAction SilentlyContinue))
  $ed = _ws-ResolveEditor
  _ws-Check "editor launcher ($ed)"  ($ed -eq 'none' -or [bool](Get-Command $ed -ErrorAction SilentlyContinue))
  $py = Get-Command python -ErrorAction SilentlyContinue; if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
  _ws-Check 'python (for ws -d)'     ([bool]$py)
  if ($py) { & $py.Source -c 'import yaml' *> $null; _ws-Check 'PyYAML (for ws -d)' ($LASTEXITCODE -eq 0) } else { _ws-Check 'PyYAML (for ws -d)' $false }
  docker compose version *> $null;   _ws-Check 'docker compose (ws -d)' ($LASTEXITCODE -eq 0)
  _ws-Check 'fzf (fuzzy picker)'     ([bool](Get-Command fzf -ErrorAction SilentlyContinue))
}

function _ws-Help {
  Write-Host @"
ws v$script:WS_VERSION — per-branch worktree workspaces (open in your editor + Claude)

  ws -n <name> [base] [-- <prompt>]  new workspace; optional Claude starting prompt
  ws            (or ws -r)           resume: pick a workspace (fzf/menu) + open it
  ws -r <name>                       resume a specific one (Claude --continue)
  ws -n/-r <name> -a <repo,repo>     also open the same-named workspace in sibling repos
  ws -a <repo,repo>                  set up your CURRENT workspace in other repos too
  ws cd [name]                       cd this shell into a workspace
  ws -l         (ls|status)          list workspaces with branch/dirty/ahead-behind
  ws -rm [name] [-f] [-b]            remove (-f force, -b also delete branch)
  ws seed [name]                     re-copy seed files (e.g. after .env changed)
  ws -d [name] [slot|off]            isolate docker stack for concurrent runs (slot 1-5)
  ws doctor                          check your environment
  ws version | -h

worktrees: $env:WS_HOME\<repo>\<name>
"@
}

function ws {
  $a = @($args)
  $cmd = if ($a.Count -ge 1) { $a[0] } else { '' }
  $rest = if ($a.Count -gt 1) { $a[1..($a.Count - 1)] } else { @() }
  switch -Regex ($cmd) {
    '^(new|-n|--new)$'                 { _ws-New $rest; break }
    '^(resume|switch|-r|--resume)$'    { _ws-Resume $rest; break }
    '^(-a|--also|also)$'               { _ws-Also $rest; break }
    '^cd$'                             { _ws-Cd $rest; break }
    '^(path|--print-dir)$'             { _ws-Path $rest; break }
    '^(ls|list|status|-l|--list)$'     { _ws-List; break }
    '^(rm|remove|-rm|--remove)$'       { _ws-Remove $rest; break }
    '^seed$'                           { _ws-SeedCmd $rest; break }
    '^(docker|-d|--docker)$'           { _ws-Docker $rest; break }
    '^doctor$'                         { _ws-Doctor; break }
    '^--list-names$'                   { _ws-Names; break }
    '^(version|-v|--version)$'         { Write-Host "ws $script:WS_VERSION"; break }
    '^(help|-h|--help)$'               { _ws-Help; break }
    '^$'                               { _ws-Resume @(); break }
    default {
      if ((_ws-InRepo) -and (Test-Path (_ws-Dir $cmd))) { _ws-Resume @($cmd) }
      else { _ws-Err "unknown command '$cmd' (new workspace? ws -n `"$cmd`")" }
    }
  }
}
