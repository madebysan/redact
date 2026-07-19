on run arguments
    set appPID to (item 1 of arguments) as integer

    tell application "System Events"
        set appProcess to missing value
        repeat 50 times
            try
                set appProcess to first process whose unix id is appPID
                exit repeat
            end try
            delay 0.1
        end repeat
        if appProcess is missing value then error "Redact accessibility process is unavailable"

        tell appProcess
            repeat 100 times
                if (count of windows) > 0 then
                    try
                        set cleanupButton to first button of group 1 of toolbar 1 of window 1 whose description is "Clean Up"
                        if enabled of cleanupButton then exit repeat
                    end try
                end if
                delay 0.1
            end repeat
            if (count of windows) is 0 then error "Cleanup project window is unavailable"
            set cleanupButton to first button of group 1 of toolbar 1 of window 1 whose description is "Clean Up"
            if cleanupButton is missing value then error "Clean Up toolbar action is missing"
            if enabled of cleanupButton is false then error "Clean Up toolbar action is disabled"

            set frontmost to true
            perform action "AXRaise" of window 1
            click cleanupButton

            repeat 50 times
                if (count of sheets of window 1) > 0 then exit repeat
                delay 0.1
            end repeat
            if (count of sheets of window 1) is 0 then error "Cleanup review sheet did not appear"
            if not (exists first checkbox of sheet 1 of window 1 whose description is "Filler words") then error "Filler category is missing"
            if not (exists first checkbox of sheet 1 of window 1 whose description is "Repeated words") then error "Repeated words category is missing"
            if not (exists first checkbox of sheet 1 of window 1 whose description is "Long pauses") then error "Long pauses category is missing"
            if not (exists button "Apply Cleanup" of sheet 1 of window 1) then error "Apply Cleanup action is missing"
            set fillerCheckbox to first checkbox of sheet 1 of window 1 whose description is "Filler words"
            if value of attribute "AXFocused" of fillerCheckbox is false then error "Cleanup category did not receive keyboard focus"

            key code 36
            repeat 50 times
                if (count of sheets of window 1) is 0 then exit repeat
                delay 0.1
            end repeat
            if (count of sheets of window 1) is not 0 then error "Cleanup review sheet did not close"
            click menu bar item "Edit" of menu bar 1
            if enabled of menu item "Undo" of menu 1 of menu bar item "Edit" of menu bar 1 is false then error "Cleanup was not recorded as an undoable edit"
            key code 53

            click first button of group 2 of toolbar 1 of window 1 whose description is "Save Project"
            delay 0.5
        end tell
    end tell

    return "PASS: reviewed cleanup applied and saved"
end run
