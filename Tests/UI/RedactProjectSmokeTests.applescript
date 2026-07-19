on run arguments
    set appPID to (item 1 of arguments) as integer

    tell application "System Events"
        set appProcess to first process whose unix id is appPID
        tell appProcess
            set frontmost to true

            repeat 100 times
                try
                    if exists first window whose name contains "sample.mov" then exit repeat
                end try
                delay 0.1
            end repeat
            if not (exists first window whose name contains "sample.mov") then error "Synthetic project did not open"
            set projectWindow to first window whose name contains "sample.mov"
            perform action "AXRaise" of projectWindow
            set value of attribute "AXMain" of projectWindow to true

            repeat 20 times
                if value of attribute "AXFocused" of text area 1 of scroll area 1 of projectWindow is true then exit repeat
                delay 0.1
            end repeat
            if value of attribute "AXFocused" of text area 1 of scroll area 1 of projectWindow is false then error "Transcript did not receive keyboard focus"

            set transcriptValue to value of text area 1 of scroll area 1 of projectWindow
            if transcriptValue does not contain "Redact makes editing direct." then error "Transcript text is missing"
            set exportButton to first button of group 2 of toolbar 1 of projectWindow whose description is "Export Video"
            if enabled of exportButton is false then error "Export is disabled for a linked project"

            keystroke "a" using command down
            repeat 50 times
                click menu bar item "Edit" of menu bar 1
                if enabled of menu item "Delete Selected" of menu 1 of menu bar item "Edit" of menu bar 1 then exit repeat
                key code 53
                set value of attribute "AXFocused" of text area 1 of scroll area 1 of projectWindow to true
                keystroke "a" using command down
                delay 0.1
            end repeat
            if enabled of menu item "Delete Selected" of menu 1 of menu bar item "Edit" of menu bar 1 is false then error "Transcript selection did not reach the edit model"
            perform action "AXPress" of menu item "Delete Selected" of menu 1 of menu bar item "Edit" of menu bar 1
            delay 0.5
            repeat 50 times
                click menu bar item "Edit" of menu bar 1
                if enabled of menu item "Undo" of menu 1 of menu bar item "Edit" of menu bar 1 then exit repeat
                key code 53
                delay 0.1
            end repeat
            if enabled of menu item "Undo" of menu 1 of menu bar item "Edit" of menu bar 1 is false then error "Transcript deletion was not undoable"
            key code 53
            keystroke "z" using command down
            set projectWindow to front window

            set playButton to first button of projectWindow whose description is "Play"
            if playButton is missing value then error "Preview Play control is not accessible"
            key code 49
            repeat 30 times
                if description of playButton is "Pause" then exit repeat
                delay 0.1
            end repeat
            if description of playButton is not "Pause" then error "Preview did not start playback"
            key code 49
        end tell
    end tell

    return "PASS: transcript, preview, delete, undo, and playback"
end run
