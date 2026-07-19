on run arguments
    set appPID to (item 1 of arguments) as integer

    tell application "System Events"
        set appProcess to first process whose unix id is appPID
        tell appProcess
            set frontmost to true

            -- A freshly built release bundle can take longer to present its first
            -- window while macOS performs cold-start validation and indexing.
            repeat 300 times
                if (count of windows) > 0 then exit repeat
                delay 0.1
            end repeat
            if (count of windows) is 0 then error "Redact did not open a window"

            if not (exists button "Import Media" of window 1) then error "Import Media button is missing"
            set importButton to button "Import Media" of window 1
            if enabled of importButton is false then error "Import Media button is disabled"

            click importButton
            repeat 50 times
                if (count of sheets of window 1) > 0 then exit repeat
                delay 0.1
            end repeat
            if (count of sheets of window 1) is 0 then error "Import Media did not open a file chooser"

            if not (exists button "Cancel" of splitter group 1 of sheet 1 of window 1) then error "Import file chooser has no Cancel action"
            set cancelButton to button "Cancel" of splitter group 1 of sheet 1 of window 1
            click cancelButton

            repeat 50 times
                if (count of sheets of window 1) is 0 then exit repeat
                delay 0.1
            end repeat
            if (count of sheets of window 1) is not 0 then error "Import file chooser did not close"
        end tell
    end tell

    return "PASS: launch and import chooser"
end run
