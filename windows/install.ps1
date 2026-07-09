# ws installer (Windows / PowerShell). Idempotent — safe to re-run.
#   powershell -ExecutionPolicy Bypass -File windows\install.ps1
$ErrorActionPreference = 'Stop'

$repo = Split-Path $PSScriptRoot -Parent
$dest = Join-Path $HOME '.config\ws'

Write-Host "==> installing ws to $dest"
New-Item -ItemType Directory -Force -Path $dest, (Join-Path $HOME 'worktrees') | Out-Null
Copy-Item -Force (Join-Path $repo 'windows\ws.ps1')          $dest
Copy-Item -Force (Join-Path $repo 'common\gen_override.py')  $dest

if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Force -Path $PROFILE | Out-Null }
if (Select-String -Quiet -SimpleMatch 'ws.ps1' $PROFILE) {
  Write-Host "==> $PROFILE already wired, skipping"
} else {
  Write-Host "==> wiring ws into $PROFILE"
  Add-Content $PROFILE (Get-Content (Join-Path $repo 'windows\profile-snippet.ps1') -Raw)
}

# Keep the .ws-autoclaude marker out of `git status` everywhere.
$gexcl = git config --global core.excludesfile
if (-not $gexcl) { $gexcl = Join-Path $HOME '.gitignore_global'; git config --global core.excludesfile $gexcl }
$gexcl = $gexcl -replace '^~', $HOME
if (-not (Test-Path $gexcl)) { New-Item -ItemType File -Force -Path $gexcl | Out-Null }
if (-not (Select-String -Quiet -SimpleMatch '.ws-autoclaude' $gexcl)) {
  Add-Content $gexcl "`n# ws workspace marker`n.ws-autoclaude"
}

Write-Host "==> done. Open a new PowerShell (or: . `$PROFILE), then: ws -n my-branch"
