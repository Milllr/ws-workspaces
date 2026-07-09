# ws installer (Windows / PowerShell). Idempotent — safe to re-run.
#   powershell -ExecutionPolicy Bypass -File install\install.ps1
$ErrorActionPreference = 'Stop'

$repo = Split-Path $PSScriptRoot -Parent
$dest = Join-Path $HOME '.config\ws'

Write-Host "==> installing ws -> $dest"
New-Item -ItemType Directory -Force -Path $dest, (Join-Path $dest 'seed'), (Join-Path $HOME 'worktrees') | Out-Null
Copy-Item -Force (Join-Path $repo 'bin\ws.ps1')          $dest
Copy-Item -Force (Join-Path $repo 'common\gen_override.py') $dest
Copy-Item -Force (Join-Path $repo 'shell\hook.ps1')      $dest
Copy-Item -Force (Join-Path $repo 'config.example')      (Join-Path $dest 'config.example')

if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Force -Path $PROFILE | Out-Null }

# Replaceable sentinel block.
$lines = @(Get-Content $PROFILE -ErrorAction SilentlyContinue)
$out = New-Object System.Collections.Generic.List[string]
$skip = $false
foreach ($l in $lines) {
  if ($l -match '^# >>> ws >>>') { $skip = $true; continue }
  if ($skip) { if ($l -match '^# <<< ws <<<') { $skip = $false }; continue }
  if ($l -match 'ws\.ps1') { continue }   # drop legacy v1 dot-source line
  $out.Add($l)
}
$out.Add('')
$out.Add('# >>> ws >>>')
$out.Add('. "$HOME\.config\ws\hook.ps1"')
$out.Add('# <<< ws <<<')
Set-Content -Path $PROFILE -Value $out
Write-Host "==> wired $PROFILE"

# Keep the .ws-autoclaude marker out of `git status` everywhere.
$gexcl = git config --global core.excludesfile
if (-not $gexcl) { $gexcl = Join-Path $HOME '.gitignore_global'; git config --global core.excludesfile $gexcl }
$gexcl = $gexcl -replace '^~', $HOME
if (-not (Test-Path $gexcl)) { New-Item -ItemType File -Force -Path $gexcl | Out-Null }
if (-not (Select-String -Quiet -SimpleMatch '.ws-autoclaude' $gexcl)) {
  Add-Content $gexcl "`n# ws workspace marker`n.ws-autoclaude"
}

Write-Host "==> done. Open a new PowerShell (or: . `$PROFILE), then: ws doctor"
