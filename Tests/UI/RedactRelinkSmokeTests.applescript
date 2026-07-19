on run arguments
    set appPID to (item 1 of arguments) as integer
    set mediaPath to item 2 of arguments

    tell application "System Events"
        set appProcess to first process whose unix id is appPID
        tell appProcess
            set frontmost to true
            set projectWindow to window 1

            repeat 100 times
                if (count of windows) > 0 then
                    try
                        if exists button "Relink Media…" of window 1 then exit repeat
                    end try
                end if
                delay 0.1
            end repeat
            if not (exists button "Relink Media…" of window 1) then error "Missing-media recovery action did not appear"
            click menu bar item "File" of menu bar 1
            if enabled of menu item "Export Media…" of menu 1 of menu bar item "File" of menu bar 1 then error "Export is enabled before media recovery"

            click menu item "Relink Media…" of menu 1 of menu bar item "File" of menu bar 1
            repeat 50 times
                if (count of sheets of window 1) > 0 then exit repeat
                delay 0.1
            end repeat
            if (count of sheets of window 1) is 0 then error "Relink file chooser did not appear"

            keystroke "g" using {command down, shift down}
            delay 0.2
            keystroke mediaPath
            key code 36
            delay 0.3
            click button "Relink" of splitter group 1 of sheet 1 of projectWindow

            repeat 400 times
                if (count of sheets of projectWindow) is 0 and not (exists button "Relink Media…" of projectWindow) then exit repeat
                delay 0.1
            end repeat
            if (count of sheets of projectWindow) is not 0 then error "Relink file chooser did not close"
            if exists button "Relink Media…" of projectWindow then error "Missing-media notice remained after relink"

            click menu bar item "File" of menu bar 1
            if enabled of menu item "Export Media…" of menu 1 of menu bar item "File" of menu bar 1 is false then error "Relink did not restore editing and export"
            key code 53

            keystroke "s" using command down
            delay 0.5
        end tell
    end tell

    return "PASS: missing media relinked"
end run
