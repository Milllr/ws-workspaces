# ws — PowerShell integration. Installed to ~/.config/ws/hook.ps1 and dot-sourced
# from $PROFILE. Loads the `ws` command, adds marker auto-start + tab-completion.

. "$HOME\.config\ws\ws.ps1"

# Auto-start Claude in a workspace terminal. The marker is a QUEUE (one launch
# spec per line: fresh|continue|resume <uuid>|prompt <text>); each new terminal
# pops the first line, so N terminals resume N Claude sessions.
$__m = Join-Path (Get-Location) '.ws-autoclaude'
if ((Test-Path $__m) -and -not $env:WS_CLAUDE_STARTED) {
  $__ttl = if ($env:WS_MARKER_TTL) { [int]$env:WS_MARKER_TTL } else { 1440 }
  if (((Get-Date) - (Get-Item $__m).LastWriteTime).TotalMinutes -gt $__ttl) {
    Remove-Item -Force $__m -ErrorAction SilentlyContinue
  } else {
    $env:WS_CLAUDE_STARTED = '1'
    $__lines = @(Get-Content $__m -ErrorAction SilentlyContinue)
    $__spec = if ($__lines.Count -ge 1) { $__lines[0] } else { '' }
    if ($__lines.Count -ge 2) { Set-Content -Path $__m -Value ($__lines[1..($__lines.Count - 1)]) }
    else { Remove-Item -Force $__m -ErrorAction SilentlyContinue }
    if (Get-Command claude -ErrorAction SilentlyContinue) {
      $__mode = ($__spec -split ' ', 2)[0]
      $__payload = if ($__spec -match ' ') { ($__spec -split ' ', 2)[1] } else { '' }
      switch ($__mode) {
        'continue' { claude --continue }
        'resume'   { claude --resume $__payload }
        'prompt'   { claude $__payload }
        default    { claude }
      }
    }
  }
}

# Tab-completion: subcommands + this repo's workspace names.
Register-ArgumentCompleter -CommandName ws -ScriptBlock {
  param($word, $ast, $pos)
  $subs = 'new', 'resume', 'switch', 'also', 'update', 'save', 'restore', 'sessions', 'cd', 'ls', 'list', 'status', 'rm', 'remove', 'seed', 'docker', 'doctor', 'version', 'help'
  $names = try { _ws-Names } catch { @() }
  ($subs + $names) | Where-Object { $_ -like "$word*" } |
    ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
