// =============================
// File: DropletBuilder.swift - Complete file with Assets catalog icon support
// =============================

import Foundation
import AppKit

final class DropletBuilder {
    static let shared = DropletBuilder()
    
    private init() {}
    
    // MARK: - Public Interface
    
    /// Create an AppleScript droplet application that will launch MrHEVC with preset settings
    func createDroplet(presetName: String, settings: Settings, at outputURL: URL) throws {
        // 1. Load and substitute template
        let scriptContent = try loadAndSubstituteTemplate(presetName: presetName, settings: settings)
        
        // 2. Create temporary .scpt file
        let tempDir = FileManager.default.temporaryDirectory
        let tempScriptURL = tempDir.appendingPathComponent("\(UUID().uuidString).scpt")
        
        try scriptContent.write(to: tempScriptURL, atomically: true, encoding: .utf8)
        
        // 3. Compile to application bundle
        try compileToApplication(scriptURL: tempScriptURL, outputURL: outputURL)
        
        // 4. Clean up temporary file
        try? FileManager.default.removeItem(at: tempScriptURL)
        
        // 5. Set custom icon - now with better error handling
        do {
            try setDropletIcon(at: outputURL)
        } catch {
            print("⚠️ Could not set droplet icon: \(error)")
            // Don't fail the entire droplet creation for icon issues
        }
        
        // 6. Set additional metadata
        try setDropletMetadata(at: outputURL, presetName: presetName)
    }
    
    /// Show save dialog and create droplet
    func showCreateDropletDialog(presetName: String, settings: Settings, completion: @escaping (Bool) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Create Droplet"
        panel.message = "Save this preset as a drag-and-drop application"
        panel.nameFieldStringValue = "\(presetName) Droplet"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canCreateDirectories = true
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            
            do {
                try self.createDroplet(presetName: presetName, settings: settings, at: url)
                completion(true)
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Droplet Creation Failed"
                    alert.informativeText = "Could not create droplet: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
                completion(false)
            }
        }
    }
    
    // MARK: - Template Processing
    
    private func loadAndSubstituteTemplate(presetName: String, settings: Settings) throws -> String {
        // 1. Try multiple ways to find the template
        var templateURL: URL?
        
        // Method 1: Look for template file (using .template extension to avoid compilation)
        templateURL = Bundle.main.url(forResource: "DropletScript.applescript", withExtension: "template")
        
        // Method 2: Look for .txt version
        if templateURL == nil {
            templateURL = Bundle.main.url(forResource: "DropletScript", withExtension: "txt")
        }
        
        // Method 3: Look for source .applescript file (if not compiled)
        if templateURL == nil {
            templateURL = Bundle.main.url(forResource: "DropletScript", withExtension: "applescript")
        }
        
        // Method 4: Bundle.main.path + manual URL construction
        if templateURL == nil {
            let possibleExtensions = ["template", "txt", "applescript"]
            for ext in possibleExtensions {
                if let path = Bundle.main.path(forResource: "DropletScript.applescript", ofType: ext) {
                    templateURL = URL(fileURLWithPath: path)
                    break
                }
                if let path = Bundle.main.path(forResource: "DropletScript", ofType: ext) {
                    templateURL = URL(fileURLWithPath: path)
                    break
                }
            }
        }
        
        guard let finalURL = templateURL else {
            // Provide detailed debugging info
            let resourcePath = Bundle.main.resourcePath ?? "nil"
            let bundlePath = Bundle.main.bundlePath
            let executablePath = Bundle.main.executablePath ?? "nil"
            
            let debugInfo = """
            DropletScript.applescript template file not found in app bundle.
            
            Debug info:
            - Bundle path: \(bundlePath)
            - Resource path: \(resourcePath)
            - Executable path: \(executablePath)
            
            Please ensure DropletScript.applescript is added to the "Copy Bundle Resources" build phase in Xcode.
            """
            
            print(debugInfo)
            throw DropletError.templateNotFound
        }
        
        let template = try String(contentsOf: finalURL, encoding: .utf8)
        
        // 2. Encode settings as JSON
        let settingsJSON = try encodeSettingsAsJSON(settings)
        
        // 3. Get bundle ID
        let bundleID = Bundle.main.bundleIdentifier ?? "com.yourcompany.MrHEVC"
        
        // 4. Get creation date
        let creationDate = DateFormatter.dropletTimestamp.string(from: Date())
        
        // 5. Escape values for AppleScript
        let escapedPresetName = escapeForAppleScript(presetName)
        let escapedSettingsJSON = escapeForAppleScript(settingsJSON)
        let escapedBundleID = escapeForAppleScript(bundleID)
        let escapedCreationDate = escapeForAppleScript(creationDate)
        
        // 6. Substitute placeholders
        let substitutions: [String: String] = [
            "{{PRESET_NAME}}": escapedPresetName,
            "{{SETTINGS_JSON}}": escapedSettingsJSON,
            "{{BUNDLE_ID}}": escapedBundleID,
            "{{CREATION_DATE}}": escapedCreationDate
        ]
        
        var result = template
        for (placeholder, value) in substitutions {
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        
        return result
    }
    
    private func escapeForAppleScript(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")  // Escape backslashes first
            .replacingOccurrences(of: "\"", with: "\\\"")  // Then escape quotes
            .replacingOccurrences(of: "\n", with: "\\n")   // Escape newlines
            .replacingOccurrences(of: "\r", with: "\\r")   // Escape carriage returns
    }
    
    func encodeSettingsAsJSON(_ settings: Settings, presetName: String = "Droplet") throws -> String {
        let dropletFile = DropletFile(presetName: presetName, settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(dropletFile)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw DropletError.encodingFailed
        }
        return jsonString
    }
    
    // MARK: - Compilation
    
    private func compileToApplication(scriptURL: URL, outputURL: URL) throws {
        // Remove existing output if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        process.arguments = [
            "-o", outputURL.path,
            scriptURL.path
        ]
        
        let pipe = Pipe()
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown compilation error"
            throw DropletError.compilationFailed(errorMessage)
        }
    }
    
    // MARK: - Icon Handling
    
    private func setDropletIcon(at dropletURL: URL) throws {
        let fm = FileManager.default
        
        // 1. First, try to copy the app's icon file directly
        if let mainIconURL = findMainAppIcon() {
            let dropletIconURL = dropletURL.appendingPathComponent("Contents/Resources/droplet.icns")
            
            // Ensure Resources directory exists
            try fm.createDirectory(
                at: dropletIconURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            do {
                // Remove existing icon if present
                try? fm.removeItem(at: dropletIconURL)
                
                // Copy main app icon
                try fm.copyItem(at: mainIconURL, to: dropletIconURL)
                print("✅ Copied app icon to droplet")
                
                // 2. Update the droplet's Info.plist to use the icon
                try updateDropletInfoPlist(at: dropletURL)
                
                // 3. Set file icon programmatically for immediate visibility
                try setFileIcon(dropletURL: dropletURL, iconURL: dropletIconURL)
                
                return
            } catch {
                print("⚠️ Failed to copy icon file: \(error), trying programmatic approach")
            }
        }
        
        // Fallback: Try to set icon programmatically using NSWorkspace
        try setIconProgrammatically(at: dropletURL)
    }
    
    private func findMainAppIcon() -> URL? {
        let bundle = Bundle.main
        
        // First, try to load from Assets catalog (modern approach)
        if let customIcon = NSImage(named: "DropletIcon.icns") {
            // Create a temporary file from the NSImage since we need a URL
            return createTempIconFile(from: customIcon, name: "DropletIcon")
        }
        
        // Try other possible asset names
        let assetNames = [
            "DropletIcon",
            "MrHEVC-Droplet",
            "droplet-icon"
        ]
        
        for assetName in assetNames {
            if let customIcon = NSImage(named: assetName) {
                print("✅ Found custom droplet icon in Assets: \(assetName)")
                return createTempIconFile(from: customIcon, name: assetName)
            }
        }
        
        print("⚠️ Custom droplet icon not found in Assets, trying bundle files...")
        
        // Fallback: try to find loose .icns files in bundle
        let dropletIconNames = [
            "DropletIcon",
            "DropletIcon.icns",
            "mrHEVC_dropper_icon",        // Add your specific filename
            "mrHEVC_dropper_icon.png",    // Try with extension
            "MrHEVC-Droplet",
            "MrHEVC-Droplet.icns",
            "droplet-icon",
            "droplet-icon.icns"
        ]
        
        for name in dropletIconNames {
            if let iconURL = bundle.url(forResource: name, withExtension: "icns") {
                print("✅ Found custom droplet icon file: \(name)")
                return iconURL
            }
            if let iconURL = bundle.url(forResource: name, withExtension: "png") {
                print("✅ Found custom droplet icon PNG: \(name)")
                return iconURL
            }
            if let iconURL = bundle.url(forResource: name, withExtension: nil) {
                print("✅ Found custom droplet icon file: \(name)")
                return iconURL
            }
        }
        
        print("⚠️ Custom droplet icon not found, falling back to main app icon")
        
        // Fallback to main app icon from Assets
        if let mainIcon = NSImage(named: "AppIcon") {
            print("✅ Found main app icon in Assets")
            return createTempIconFile(from: mainIcon, name: "AppIcon")
        }
        
        // Fallback to main app icon files
        let mainIconNames = [
            "AppIcon",
            "AppIcon.icns",
            "app.icns",
            "MrHEVC",
            "MrHEVC.icns"
        ]
        
        for name in mainIconNames {
            if let iconURL = bundle.url(forResource: name, withExtension: "icns") {
                print("✅ Found main app icon file: \(name)")
                return iconURL
            }
            if let iconURL = bundle.url(forResource: name, withExtension: nil) {
                print("✅ Found main app icon file: \(name)")
                return iconURL
            }
        }
        
        // Try to get icon from Info.plist
        if let iconFileName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            let cleanName = iconFileName.replacingOccurrences(of: ".icns", with: "")
            if let iconURL = bundle.url(forResource: cleanName, withExtension: "icns") {
                print("✅ Found icon from Info.plist: \(cleanName)")
                return iconURL
            }
        }
        
        print("⚠️ Could not find any app icon")
        return nil
    }
    
    private func createTempIconFile(from image: NSImage, name: String) -> URL? {
        // Create a temporary .icns file from NSImage
        let tempDir = FileManager.default.temporaryDirectory
        let tempIconURL = tempDir.appendingPathComponent("\(name)_\(UUID().uuidString).png")
        
        // Convert NSImage to PNG data (simpler than ICNS)
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            print("⚠️ Could not create PNG representation")
            return nil
        }
        
        do {
            try pngData.write(to: tempIconURL)
            print("✅ Created temp icon file: \(tempIconURL.lastPathComponent)")
            return tempIconURL
        } catch {
            print("⚠️ Could not write temp icon file: \(error)")
            return nil
        }
    }
    
    private func updateDropletInfoPlist(at dropletURL: URL) throws {
        let infoPlistURL = dropletURL.appendingPathComponent("Contents/Info.plist")
        
        guard let plistData = try? Data(contentsOf: infoPlistURL),
              var plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            print("⚠️ Could not read droplet Info.plist")
            return
        }
        
        // Set the icon file reference
        plist["CFBundleIconFile"] = "droplet.icns"
        
        // Write back to plist
        let updatedData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try updatedData.write(to: infoPlistURL)
        
        print("✅ Updated droplet Info.plist with icon reference")
    }
    
    private func setFileIcon(dropletURL: URL, iconURL: URL) throws {
        // Use NSWorkspace to set the file icon
        let workspace = NSWorkspace.shared
        
        if let image = NSImage(contentsOf: iconURL) {
            workspace.setIcon(image, forFile: dropletURL.path, options: [])
            print("✅ Set droplet file icon programmatically")
        }
    }
    
    private func setIconProgrammatically(at dropletURL: URL) throws {
        let workspace = NSWorkspace.shared
        
        // Try to get the custom droplet icon from Assets first
        if let customIcon = NSImage(named: "DropletIcon") {
            workspace.setIcon(customIcon, forFile: dropletURL.path, options: [])
            print("✅ Set custom droplet icon from Assets programmatically")
            return
        }
        
        // Try with .icns extension in case that's how it's named
        if let customIcon = NSImage(named: "DropletIcon.icns") {
            workspace.setIcon(customIcon, forFile: dropletURL.path, options: [])
            print("✅ Set custom droplet icon 'DropletIcon.icns' from Assets programmatically")
            return
        }
        
        // Try other asset names
        let assetNames = ["MrHEVC-Droplet", "droplet-icon"]
        for assetName in assetNames {
            if let customIcon = NSImage(named: assetName) {
                workspace.setIcon(customIcon, forFile: dropletURL.path, options: [])
                print("✅ Set custom droplet icon '\(assetName)' programmatically")
                return
            }
        }
        
        // Try to find custom icon file
        if let customIconURL = findMainAppIcon(),
           let customIcon = NSImage(contentsOf: customIconURL) {
            workspace.setIcon(customIcon, forFile: dropletURL.path, options: [])
            print("✅ Set custom droplet icon from file programmatically")
            return
        }
        
        // Fallback: Get the main app's icon from Assets
        if let appIcon = NSImage(named: "AppIcon") {
            workspace.setIcon(appIcon, forFile: dropletURL.path, options: [])
            print("✅ Set main app icon from Assets as droplet icon")
            return
        }
        
        // Final fallback: Get the main app's icon from bundle
        let mainAppURL = Bundle.main.bundleURL
        if let appIcon = workspace.icon(forFile: mainAppURL.path).copy() as? NSImage {
            workspace.setIcon(appIcon, forFile: dropletURL.path, options: [])
            print("✅ Set app bundle icon as droplet icon programmatically")
        } else {
            print("⚠️ Could not get any icon for droplet")
            throw DropletError.fileSystemError("Could not set droplet icon")
        }
    }
    
    private func setDropletMetadata(at dropletURL: URL, presetName: String) throws {
        // Set file attributes to make it clear this is a droplet
        // Note: localizedName is read-only, so we'll just set what we can
        do {
            // Try to set some basic attributes via extended attributes
            let displayName = "\(presetName) Droplet"
            let xattrKey = "com.apple.metadata:kMDItemDisplayName"
            let xattrValue = displayName.data(using: .utf8) ?? Data()
            
            let result = setxattr(dropletURL.path, xattrKey, xattrValue.withUnsafeBytes { $0.baseAddress }, xattrValue.count, 0, 0)
            if result == 0 {
                print("✅ Set droplet extended attributes")
            } else {
                print("⚠️ Could not set extended attributes, but continuing...")
            }
        } catch {
            print("⚠️ Could not set droplet metadata: \(error)")
            // Don't throw - this is not critical
        }
    }
}

// MARK: - Errors

enum DropletError: LocalizedError {
    case templateNotFound
    case encodingFailed
    case compilationFailed(String)
    case fileSystemError(String)
    
    var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return "DropletScript.applescript template file not found in app bundle"
        case .encodingFailed:
            return "Failed to encode preset settings"
        case .compilationFailed(let message):
            return "AppleScript compilation failed: \(message)"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        }
    }
}

// MARK: - DateFormatter Extension
private extension DateFormatter {
    static let dropletTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
