on run arguments
    set appPID to (item 1 of arguments) as integer
    set outputDirectory to item 2 of arguments

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
                        set exportButton to first button of group 2 of toolbar 1 of window 1 whose description is "Export Video"
                        if enabled of exportButton then exit repeat
                    end try
                end if
                delay 0.1
            end repeat
            if (count of windows) is 0 then error "Project window is unavailable for export"
            set exportButton to first button of group 2 of toolbar 1 of window 1 whose description is "Export Video"
            if enabled of exportButton is false then error "Project did not become exportable"
            set projectWindow to window 1
            set frontmost to true
            perform action "AXRaise" of projectWindow
            set value of attribute "AXMain" of projectWindow to true

            -- Subtitle export through the File menu.
            click menu item "Export SRT…" of menu 1 of menu bar item "File" of menu bar 1
            my chooseSaveDestination(appProcess, projectWindow, outputDirectory, "smoke-subtitles.srt")
            my waitForNoSheet(appProcess, projectWindow)

            -- Default MP4 video export through the product export sheet.
            set frontmost to true
            click exportButton
            my waitForSheet(appProcess, projectWindow)
            if value of attribute "AXFocused" of pop up button 1 of sheet 1 of projectWindow is false then error "Export format did not receive keyboard focus"
            key code 36
            delay 0.3
            my chooseSaveDestination(appProcess, projectWindow, outputDirectory, "smoke-video.mp4")
            my waitForExportCompletion(appProcess, projectWindow)

            -- MP3 verifies the audio-only path, not just a video container copy.
            delay 0.3
            set frontmost to true
            click exportButton
            my waitForSheet(appProcess, projectWindow)
            click pop up button 1 of sheet 1 of projectWindow
            click menu item "MP3 Audio" of menu 1 of pop up button 1 of sheet 1 of projectWindow
            repeat 20 times
                if value of pop up button 1 of sheet 1 of projectWindow is "MP3 Audio" then exit repeat
                delay 0.1
            end repeat
            if value of pop up button 1 of sheet 1 of projectWindow is not "MP3 Audio" then error "MP3 format was not selected"
            repeat 20 times
                if exists button "Export Audio" of sheet 1 of projectWindow then exit repeat
                delay 0.1
            end repeat
            if not (exists button "Export Audio" of sheet 1 of projectWindow) then error "Audio export action did not appear"
            perform action "AXPress" of button "Export Audio" of sheet 1 of projectWindow
            delay 0.3
            my chooseSaveDestination(appProcess, projectWindow, outputDirectory, "smoke-audio.mp3")
            my waitForExportCompletion(appProcess, projectWindow)
        end tell
    end tell

    return "PASS: SRT, video, and audio exports"
end run

on chooseSaveDestination(appProcess, projectWindow, outputDirectory, fileName)
    tell application "System Events"
        tell appProcess
            repeat 50 times
                try
                    if exists button "Save" of splitter group 1 of sheet 1 of projectWindow then exit repeat
                end try
                delay 0.1
            end repeat
            if not (exists button "Save" of splitter group 1 of sheet 1 of projectWindow) then error "Export save panel did not appear"

            keystroke "g" using {command down, shift down}
            delay 0.2
            keystroke outputDirectory
            key code 36
            delay 0.3
            set value of text field "Save As:" of splitter group 1 of sheet 1 of projectWindow to fileName
            click button "Save" of splitter group 1 of sheet 1 of projectWindow
        end tell
    end tell
end chooseSaveDestination

on waitForSheet(appProcess, projectWindow)
    tell application "System Events"
        tell appProcess
            repeat 50 times
                if (count of sheets of projectWindow) > 0 then
                    try
                        if exists pop up button 1 of sheet 1 of projectWindow then exit repeat
                    end try
                end if
                delay 0.1
            end repeat
            if (count of sheets of projectWindow) is 0 then error "Expected sheet did not appear"
            if not (exists pop up button 1 of sheet 1 of projectWindow) then error "Export controls did not become accessible"
        end tell
    end tell
end waitForSheet

on waitForNoSheet(appProcess, projectWindow)
    tell application "System Events"
        tell appProcess
            repeat 50 times
                if (count of sheets of projectWindow) is 0 then exit repeat
                delay 0.1
            end repeat
            if (count of sheets of projectWindow) is not 0 then error "Save panel did not close"
        end tell
    end tell
end waitForNoSheet

on waitForExportCompletion(appProcess, projectWindow)
    tell application "System Events"
        tell appProcess
            repeat 300 times
                try
                    if exists static text "Export Complete" of sheet 1 of projectWindow then exit repeat
                    if exists static text "Export Failed" of sheet 1 of projectWindow then error "Export reported failure"
                end try
                delay 0.1
            end repeat
            if not (exists static text "Export Complete" of sheet 1 of projectWindow) then error "Export did not complete"
            if value of attribute "AXFocused" of button "Done" of sheet 1 of projectWindow is false then error "Completed export did not focus Done"
            perform action "AXPress" of button "Done" of sheet 1 of projectWindow
            repeat 50 times
                if (count of sheets of projectWindow) is 0 then exit repeat
                delay 0.1
            end repeat
            if (count of sheets of projectWindow) is not 0 then error "Completed export did not close"
        end tell
    end tell
end waitForExportCompletion
