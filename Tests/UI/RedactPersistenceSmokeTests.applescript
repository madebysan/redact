on run arguments
    set appPID to (item 1 of arguments) as integer

    tell application "System Events"
        set appProcess to first process whose unix id is appPID
        tell appProcess
            set frontmost to true
            set projectWindow to missing value
            repeat with candidateWindow in windows
                try
                    if value of text area 1 of scroll area 1 of candidateWindow contains "Redact makes editing direct." then
                        set projectWindow to candidateWindow
                        exit repeat
                    end if
                end try
            end repeat
            if projectWindow is missing value then error "No project window is open"

            perform action "AXRaise" of projectWindow
            set value of attribute "AXMain" of projectWindow to true
            click text area 1 of scroll area 1 of projectWindow
            keystroke "a" using command down
            delay 0.1

            key code 51
            repeat 20 times
                click menu bar item "Edit" of menu bar 1
                if enabled of menu item "Undo" of menu 1 of menu bar item "Edit" of menu bar 1 then exit repeat
                key code 53
                delay 0.1
            end repeat
            if enabled of menu item "Undo" of menu 1 of menu bar item "Edit" of menu bar 1 is false then error "Selected words were not deleted before save"
            key code 53

            keystroke "s" using command down
            delay 0.5
            perform action "AXPress" of (value of attribute "AXCloseButton" of projectWindow)

            repeat 50 times
                if (count of windows) is 0 then exit repeat
                delay 0.1
            end repeat
            if (count of windows) is not 0 then error "Saved project window did not close"
        end tell
    end tell

    return "PASS: edit saved and project window closed"
end run
