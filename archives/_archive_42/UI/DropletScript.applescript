-- MrHEVC Droplet: {{PRESET_NAME}}
-- Created: {{CREATION_DATE}}
-- Drag QuickTime (.mov) files onto this droplet to process them with the saved preset.

property presetData : "{{SETTINGS_JSON}}"
property mrhevcBundleID : "{{BUNDLE_ID}}"
property presetName : "{{PRESET_NAME}}"

on open droppedItems
    -- Filter for .mov files only
    set movFiles to {}
    repeat with anItem in droppedItems
        set itemPath to POSIX path of anItem
        if itemPath ends with ".mov" or itemPath ends with ".MOV" then
            set end of movFiles to itemPath
        end if
    end repeat
    
    -- Exit if no .mov files found
    if length of movFiles is 0 then
        display dialog "Please drop QuickTime (.mov) files onto this droplet." buttons {"OK"} default button 1 with icon caution
        return
    end if
    
    -- Find MrHEVC application
    try
        set mrhevcPath to findMrHEVCApp()
    on error
        display dialog "Could not find MrHEVC application. Please make sure it is installed." buttons {"OK"} default button 1 with icon stop
        return
    end try
    
    -- Create temporary preset file
    set tempFolder to (path to temporary items folder as string)
    set tempPresetFile to tempFolder & "mrhevc_droplet_" & (random number from 1000 to 9999) & ".json"
    
    try
        -- Write preset data to temp file
        set fileRef to open for access file tempPresetFile with write permission
        write presetData to fileRef
        close access fileRef
        
        -- Prepare file list for command line
        set fileArgs to ""
        repeat with aFile in movFiles
            set fileArgs to fileArgs & " " & quoted form of aFile
        end repeat
        
        -- Launch MrHEVC in CLI mode for reliable background processing
        set mrhevcExecutable to mrhevcPath & "/Contents/MacOS/MrHEVC"
        set shellCommand to quoted form of mrhevcExecutable & " --cli --droplet " & quoted form of (POSIX path of tempPresetFile) & fileArgs
        
        -- Debug: Log the command we're about to execute
        do shell script "echo 'MrHEVC Droplet: Executing CLI command:' >> /tmp/mrhevc_droplet_debug.log"
        do shell script "echo " & quoted form of shellCommand & " >> /tmp/mrhevc_droplet_debug.log"
        
        -- Execute in CLI mode (blocks until complete)
        set cliResult to do shell script shellCommand
        
        -- Log the result
        do shell script "echo 'CLI Result: " & cliResult & "' >> /tmp/mrhevc_droplet_debug.log"
        
        -- Clean up temp file immediately since CLI mode is synchronous
        try
            do shell script "rm " & quoted form of (POSIX path of tempPresetFile)
        end try
        
    on error errMsg
        try
            close access file tempPresetFile
        end try
        -- Clean up temp file on error too
        try
            do shell script "rm " & quoted form of (POSIX path of tempPresetFile)
        end try
        display dialog "Error processing files: " & errMsg buttons {"OK"} default button 1 with icon stop
    end try
end open

-- Find MrHEVC application path
on findMrHEVCApp()
    -- Try common locations
    set possiblePaths to {"/Applications/MrHEVC.app", "~/Applications/MrHEVC.app"}
    
    repeat with aPath in possiblePaths
        try
            set expandedPath to (do shell script "echo " & quoted form of aPath)
            set appExists to false
            tell application "System Events"
                if (exists file expandedPath) then
                    set appExists to true
                end if
            end tell
            
            if appExists then
                return expandedPath
            end if
        end try
    end repeat
    
    -- Try to find via bundle ID
    try
        set appPath to do shell script "mdfind 'kMDItemCFBundleIdentifier == \"" & mrhevcBundleID & "\"' | head -1"
        if appPath is not "" then
            return appPath
        end if
    end try
    
    error "MrHEVC application not found"
end findMrHEVCApp

-- Show info dialog when droplet is double-clicked
on run
    set dialogText to "This is a MrHEVC droplet for the preset: " & presetName & return & return & "To use it, drag QuickTime (.mov) files onto this application."
    display dialog dialogText buttons {"OK"} default button 1 with icon note giving up after 10
end run
