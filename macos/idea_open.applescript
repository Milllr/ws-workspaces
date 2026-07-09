-- idea_open.applescript <workspaceName> <doTerminal 0|1> <doMerge 0|1> <maxWaitSecs>
-- Best-effort IntelliJ automation: focus the workspace window, merge all project
-- windows into tabs, and open the Terminal tool window (Opt+F12) so its shell
-- starts and auto-runs claude via the ~/.zshrc marker hook.
-- Requires Accessibility permission for the terminal running `ws`.

on run argv
	set targetName to item 1 of argv
	set doTerminal to item 2 of argv
	set doMerge to item 3 of argv
	set maxWait to (item 4 of argv) as real

	tell application "IntelliJ IDEA" to activate

	tell application "System Events"
		try
			set proc to first process whose bundle identifier is "com.jetbrains.intellij"
		on error
			return
		end try

		-- Wait for the freshly-opened project window to appear.
		set waited to 0.0
		set found to false
		repeat while waited < maxWait
			try
				if (exists (first window of proc whose name contains targetName)) then
					set found to true
					exit repeat
				end if
			end try
			delay 0.4
			set waited to waited + 0.4
		end repeat

		set frontmost of proc to true
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
				set w to first window of proc whose name contains targetName
				perform action "AXRaise" of w
				delay 0.3
			end try
		end if
		set frontmost of proc to true
		delay 0.2

		-- Open the Terminal tool window (default keymap: Option+F12). Its shell
		-- starts in the project root and the ~/.zshrc hook launches claude.
		if doTerminal is "1" then
			key code 111 using {option down}
		end if
	end tell
end run
