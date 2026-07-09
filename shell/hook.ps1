# ws — PowerShell integration. Installed to ~/.config/ws/hook.ps1 and dot-sourced
# from $PROFILE. Loads the `ws` command, adds marker auto-start + tab-completion.

. "$HOME\.config\ws\ws.ps1"

# Auto-start Claude the first time a shell opens in a workspace (one-shot marker:
# line 1 = mode fresh|continue|prompt, remaining lines = prompt payload).
$__m = Join-Path (Get-Location) '.ws-autoclaude'
if ((Test-Path $__m) -and -not $env:WS_CLAUDE_STARTED) {
  $env:WS_CLAUDE_STARTED = '1'
  $__lines = @(Get-Content $__m -ErrorAction SilentlyContinue)
  Remove-Item -Force $__m -ErrorAction SilentlyContinue
  $__mode = if ($__lines.Count -ge 1) { $__lines[0] } else { '' }
  $__payload = if ($__lines.Count -ge 2) { ($__lines[1..($__lines.Count - 1)] -join "`n") } else { '' }
  if (Get-Command claude -ErrorAction SilentlyContinue) {
    switch ($__mode) {
      'continue' { claude --continue }
      'prompt'   { claude $__payload }
      default    { claude }
    }
  }
}

# Tab-completion: subcommands + this repo's workspace names.
Register-ArgumentCompleter -CommandName ws -ScriptBlock {
  param($word, $ast, $pos)
  $subs = 'new', 'resume', 'switch', 'cd', 'ls', 'list', 'status', 'rm', 'remove', 'seed', 'docker', 'doctor', 'version', 'help'
  $names = try { _ws-Names } catch { @() }
  ($subs + $names) | Where-Object { $_ -like "$word*" } |
    ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
