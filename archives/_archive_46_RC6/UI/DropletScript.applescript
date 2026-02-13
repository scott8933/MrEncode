-- MrHEVC Droplet: {{PRESET_NAME}}
-- Created: {{CREATION_DATE}}
-- Drag QuickTime (.mov / .mp4) files onto this droplet to process them with the saved preset.
-- NOTE: Codec selection (H.264 / H.265 / No Recompression) is stored inside the embedded preset JSON.

property presetData : "{{SETTINGS_JSON}}" -- JSON produced by the app (must include "codec": "hevc"|"h264"|"bypass")
property mrhevcBundleID : "{{BUNDLE_ID}}"
property presetName : "{{PRESET_NAME}}"

on open droppedItems
    -- Filter for mov/mp4 files (case-insensitive)
    set inputFiles to my filterAcceptableFiles(droppedItems)
    if (count of inputFiles) is 0 then
        display dialog "No compatible media dropped. Please drop .mov or .mp4 files." buttons {"OK"} default button 1 with icon caution giving up after 6
        return
    end if

    -- Locate MrHEVC app (by bundle id)
    set mrhevcPath to my findMrHEVCApp()
    set mrhevcExecutable to mrhevcPath & "/Contents/MacOS/MrHEVC"

    -- Create temporary preset file (HFS path)
    set tempFolder to (path to temporary items folder as string)
    set tempPresetFile to tempFolder & "mrhevc_droplet_" & (do shell script "uuidgen") & ".json"

    try
        -- Write embedded preset JSON to temp file
        set fileRef to open for access file tempPresetFile with write permission
        set eof of fileRef to 0
        write presetData to fileRef
        close access fileRef

        -- Build file list for the CLI
        set fileArgs to my joinQuoted(inputFiles)

        -- Build the CLI command line
        -- If your app uses another flag name, change "--preset-file" accordingly.
        set shellCommand to quoted form of mrhevcExecutable & " --cli --preset-file " & quoted form of (POSIX path of tempPresetFile) & fileArgs

        -- (Optional) debug: record the command
        do shell script "echo 'MrHEVC Droplet: Executing:' >> /tmp/mrhevc_droplet_debug.log"
        do shell script "echo " & quoted form of shellCommand & " >> /tmp/mrhevc_droplet_debug.log"

        -- Execute (blocks until complete)
        set cliResult to do shell script shellCommand

        -- Log the result
        do shell script "echo 'CLI Result: " & cliResult & "' >> /tmp/mrhevc_droplet_debug.log"

        -- Clean up temp file
        try
            do shell script "/bin/rm -f " & quoted form of (POSIX path of tempPresetFile)
        end try

    on error errMsg number errNum
        -- Ensure file handle is closed if we errored while writing
        try
            close access file tempPresetFile
        end try
        -- Clean up temp file on error too
        try
            do shell script "/bin/rm -f " & quoted form of (POSIX path of tempPresetFile)
        end try
        display dialog "Error processing files (" & errNum & "): " & errMsg buttons {"OK"} default button 1 with icon stop
    end try
end open

-- Show info dialog when droplet is double-clicked
on run
    set dialogText to "MrHEVC droplet for preset:" & return & "  • " & presetName & return & return & ¬
        "Drag .mov or .mp4 files onto this app to encode them using the saved preset." & return & return & ¬
        "Codec selection (H.264 / H.265 / No Recompression) is stored in the preset."
    display dialog dialogText buttons {"OK"} default button 1 with icon note giving up after 10
end run

-- Accept .mov/.mp4, case-insensitive
on filterAcceptableFiles(droppedItems)
    set outList to {}
    repeat with anItem in droppedItems
        set p to POSIX path of anItem
        ignoring case
            if p ends with ".mov" or p ends with ".mp4" then
                set end of outList to p
            end if
        end ignoring
    end repeat
    return outList
end filterAcceptableFiles

-- Find installed MrHEVC by bundle id
on findMrHEVCApp()
    try
        set appPath to do shell script "mdfind 'kMDItemCFBundleIdentifier == \"" & mrhevcBundleID & "\"' | head -1"
        if appPath is not "" then return appPath
    end try
    error "MrHEVC application not found (bundle id: " & mrhevcBundleID & ")."
end findMrHEVCApp

-- Quote every argument (POSIX paths) and join into a single string with leading spaces
on joinQuoted(posixPathList)
    set out to ""
    repeat with p in posixPathList
        set out to out & " " & quoted form of p
    end repeat
    return out
end joinQuoted
