
# ws — load the command + auto-launch Claude in a freshly-opened workspace terminal.
. "$HOME\.config\ws\ws.ps1"

# `ws -n`/`ws -r` drop a one-shot .ws-autoclaude marker in the worktree root; the
# first PowerShell that starts there (e.g. IntelliJ's terminal) consumes it and
# runs claude with any saved args ("" = fresh, "--continue" = resume).
$__wsMarker = Join-Path (Get-Location) '.ws-autoclaude'
if ((Test-Path $__wsMarker) -and -not $env:WS_CLAUDE_STARTED) {
  $env:WS_CLAUDE_STARTED = '1'
  $__wsArgs = Get-Content $__wsMarker -Raw -ErrorAction SilentlyContinue
  Remove-Item -Force $__wsMarker -ErrorAction SilentlyContinue
  if (Get-Command claude -ErrorAction SilentlyContinue) {
    if ($__wsArgs -and $__wsArgs.Trim()) { claude $__wsArgs.Trim() } else { claude }
  }
  Remove-Variable __wsArgs -ErrorAction SilentlyContinue
}
Remove-Variable __wsMarker -ErrorAction SilentlyContinue
