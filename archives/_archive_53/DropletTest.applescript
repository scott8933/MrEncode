property presetData : "{\"settings\":\"dummy\"}"
property mrencodeBundleID : "com.example.MrEncode"
property presetName : "Test Preset"

on open droppedItems
    set inputFiles to {}
    repeat with anItem in droppedItems
        set end of inputFiles to POSIX path of anItem
    end repeat
    set mrencodeExecutable to "/Applications/MrEncode.app/Contents/MacOS/MrEncode"
    set shellCommand to quoted form of mrencodeExecutable & " --cli --preset-file=" & quoted form of "/tmp/test.json" & " " & quoted form of (item 1 of inputFiles)
    display dialog shellCommand
end open
