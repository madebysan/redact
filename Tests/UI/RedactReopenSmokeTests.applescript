on run arguments
    set appPID to (item 1 of arguments) as integer

    tell application "System Events"
        set appProcess to first process whose unix id is appPID
        tell appProcess
            set frontmost to true

            set projectWindow to missing value
            repeat 100 times
                repeat with candidateWindow in windows
                    try
                        if value of text area 1 of scroll area 1 of candidateWindow contains "Redact makes editing direct." then
                            set projectWindow to candidateWindow
                            exit repeat
                        end if
                    end try
                end repeat
                if projectWindow is not missing value then exit repeat
                delay 0.1
            end repeat
            if projectWindow is missing value then error "Saved project did not reopen"

            perform action "AXRaise" of projectWindow
            set value of attribute "AXMain" of projectWindow to true
            click text area 1 of scroll area 1 of projectWindow
            keystroke "a" using command down
            delay 0.1

            click menu bar item "Edit" of menu bar 1
            if enabled of menu item "Restore Selected Words" of menu 1 of menu bar item "Edit" of menu bar 1 is false then error "Reopened project did not preserve deleted words"
            click menu item "Restore Selected Words" of menu 1 of menu bar item "Edit" of menu bar 1
            delay 0.2
            keystroke "s" using command down
            delay 0.5
        end tell
    end tell

    return "PASS: saved edit reopened and restored"
end run
