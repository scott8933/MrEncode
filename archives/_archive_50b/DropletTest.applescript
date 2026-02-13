property presetData : "{\"settings\":\"dummy\"}"
property mrhevcBundleID : "com.example.MrHEVC"
property presetName : "Test Preset"

on open droppedItems
    set inputFiles to {}
    repeat with anItem in droppedItems
        set end of inputFiles to POSIX path of anItem
    end repeat
    set mrhevcExecutable to "/Applications/MrHEVC.app/Contents/MacOS/MrHEVC"
    set shellCommand to quoted form of mrhevcExecutable & " --cli --preset-file=" & quoted form of "/tmp/test.json" & " " & quoted form of (item 1 of inputFiles)
    display dialog shellCommand
end open
