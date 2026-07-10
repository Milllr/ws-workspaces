-- idea_open.applescript <workspaceName> <doTerminal 0|1> <doMerge 0|1> <maxWaitSecs>
-- Best-effort IntelliJ automation after `idea <dir>`:
--   1. If the "Open Project" prompt appears (a project is already open), click
--      "New Window" so the workspace ALWAYS opens in its own window.
--   2. Merge all project windows into tabs of one window.
--   3. Open the Terminal tool window (Opt+F12) so its shell starts in the worktree
--      and the shell hook auto-launches claude via the .ws-autoclaude marker.
-- Requires Accessibility + Automation permission for the app running `ws`.
--
-- Everything goes through System Events (not `tell application "IntelliJ IDEA"`),
-- because a modal dialog makes IntelliJ stop answering Apple Events (-1712). The
-- prompt's buttons expose no AX name/title — their label is the AX 'description'
-- (Cancel / New Window / This Window), so we match on that. All fragile calls are
-- wrapped in `try` so a slow/absent element can never abort the run.

on run argv
	set targetName to item 1 of argv
	set doTerminal to item 2 of argv
	set doMerge to item 3 of argv
	set maxWait to (item 4 of argv) as real

	tell application "System Events"
		-- Wait for the IntelliJ process (handles a cold start from `idea`).
		set proc to missing value
		set waited to 0.0
		repeat while waited < maxWait
			try
				set proc to first process whose bundle identifier is "com.jetbrains.intellij"
			end try
			if proc is not missing value then exit repeat
			delay 0.3
			set waited to waited + 0.3
		end repeat
		if proc is missing value then return
		try
			set frontmost of proc to true
		end try

		-- Poll for our project window; if the modal "Open Project" prompt is up
		-- (frontmost = window 1), click its New Window button.
		set found to false
		set waited to 0.0
		repeat while waited < maxWait
			try
				if (exists (first window of proc whose name contains targetName)) then
					set found to true
					exit repeat
				end if
			end try
			try
				click (first button of window 1 of proc whose description is "New Window")
			end try
			delay 0.3
			set waited to waited + 0.3
		end repeat

		try
			set frontmost of proc to true
		end try
		delay 0.3

		-- Merge separate project windows into tabs of one window.
		if doMerge is "1" then
			try
				click menu item "Merge All Project Windows" of menu "Window" of menu bar 1 of proc
				delay 0.6
			end try
		end if

		-- Bring our workspace tab to the front.
		if found then
			try
				perform action "AXRaise" of (first window of proc whose name contains targetName)
				delay 0.3
			end try
		end if
		try
			set frontmost of proc to true
		end try
		delay 0.2

		-- Open the Terminal tool window (default keymap: Option+F12). Its shell
		-- starts in the project root and the shell hook launches claude.
		if doTerminal is "1" then
			key code 111 using {option down}
		end if
	end tell
end run
