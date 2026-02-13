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
            try setDropletIcon(at: outputURL, settings: settings)
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
            throw DropletBuilderError.templateNotFound
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
            "{{CREATION_DATE}}": escapedCreationDate,
            "{{APP_PATH}}": escapeForAppleScript(Bundle.main.bundlePath)
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
            throw DropletBuilderError.encodingFailed
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
            throw DropletBuilderError.compilationFailed(errorMessage)
        }
    }
    
    // MARK: - Icon Handling
    
    private func setDropletIcon(at dropletURL: URL, settings: Settings) throws {
        let fm = FileManager.default
        var copiedICNS = false

        if let mainIconURL = findDropletIcon(for: settings), mainIconURL.pathExtension.lowercased() == "icns" {
            let dropletIconURL = dropletURL.appendingPathComponent("Contents/Resources/droplet.icns")

            try fm.createDirectory(
                at: dropletIconURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            do {
                try? fm.removeItem(at: dropletIconURL)
                try fm.copyItem(at: mainIconURL, to: dropletIconURL)
                try updateDropletInfoPlist(at: dropletURL)
                try setFileIcon(dropletURL: dropletURL, iconURL: dropletIconURL)
                print("✅ Copied app icon to droplet")
                copiedICNS = true
            } catch {
                print("⚠️ Failed to copy icon file: \(error). Falling back to programmatic icon assignment.")
            }
        }

        if !copiedICNS {
            try updateDropletInfoPlist(at: dropletURL)
            try setIconProgrammatically(at: dropletURL, settings: settings)
        }
    }
    
    private func findDropletIcon(for settings: Settings) -> URL? {
        let bundle = Bundle.main
        
        // Determine which icon to use based on run mode
        let iconBaseName = (settings.runMode == .remoteDeadline) ? "DropletIconRemote" : "DropletIcon"
        
        print("🔍 Looking for droplet icon: \(iconBaseName) (runMode: \(settings.runMode.rawValue))")
        
        // First, try to load from Assets catalog (modern approach)
        if let customIcon = NSImage(named: iconBaseName) {
            print("✅ Found \(iconBaseName) in Assets catalog")
            return createTempIconFile(from: customIcon, name: iconBaseName)
        }
        
        // Try with .icns extension in assets
        if let customIcon = NSImage(named: "\(iconBaseName).icns") {
            print("✅ Found \(iconBaseName).icns in Assets catalog")
            return createTempIconFile(from: customIcon, name: "\(iconBaseName).icns")
        }
        
        // Try with .icon extension in assets
        if let customIcon = NSImage(named: "\(iconBaseName).icon") {
            print("✅ Found \(iconBaseName).icon in Assets catalog")
            return createTempIconFile(from: customIcon, name: "\(iconBaseName).icon")
        }
        
        print("⚠️ \(iconBaseName) not found in Assets, trying bundle files...")
        
        // Try to find loose files in bundle with various extensions
        let extensions = ["icon", "icns", "png"]
        
        for ext in extensions {
            if let iconURL = bundle.url(forResource: iconBaseName, withExtension: ext) {
                print("✅ Found \(iconBaseName).\(ext) in bundle")
                return iconURL
            }
        }
        
        // Try without extension (in case the file has extension in name)
        if let iconURL = bundle.url(forResource: iconBaseName, withExtension: nil) {
            print("✅ Found \(iconBaseName) in bundle (no extension)")
            return iconURL
        }
        
        print("⚠️ \(iconBaseName) not found, falling back to generic DropletIcon")
        
        // Fallback to generic DropletIcon
        if iconBaseName != "DropletIcon" {
            // First try Assets
            if let fallbackIcon = NSImage(named: "DropletIcon") {
                print("✅ Using fallback DropletIcon from Assets")
                return createTempIconFile(from: fallbackIcon, name: "DropletIcon")
            }
            
            // Try with extensions
            for ext in extensions {
                if let iconURL = bundle.url(forResource: "DropletIcon", withExtension: ext) {
                    print("✅ Using fallback DropletIcon.\(ext) from bundle")
                    return iconURL
                }
            }
        }
        
        print("⚠️ No droplet-specific icon found, falling back to main app icon")
        return findMainAppIcon()
    }
    
    private func findMainAppIcon() -> URL? {
        let bundle = Bundle.main
        
        // Fallback to main app icon from Assets
        if let mainIcon = NSImage(named: "AppIcon") {
            print("✅ Found main app icon in Assets")
            return createTempIconFile(from: mainIcon, name: "AppIcon")
        }
        
        // Fallback to main app icon files
        let mainIconNames = [
            "AppIcon",
            "app",
            "MrHEVC"
        ]
        
        let extensions = ["icon", "icns", "png"]
        
        for name in mainIconNames {
            for ext in extensions {
                if let iconURL = bundle.url(forResource: name, withExtension: ext) {
                    print("✅ Found main app icon file: \(name).\(ext)")
                    return iconURL
                }
            }
            
            // Try without extension
            if let iconURL = bundle.url(forResource: name, withExtension: nil) {
                print("✅ Found main app icon file: \(name)")
                return iconURL
            }
        }
        
        // Try to get icon from Info.plist
        if let iconFileName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            let cleanName = iconFileName.replacingOccurrences(of: ".icns", with: "").replacingOccurrences(of: ".icon", with: "")
            
            for ext in extensions {
                if let iconURL = bundle.url(forResource: cleanName, withExtension: ext) {
                    print("✅ Found icon from Info.plist: \(cleanName).\(ext)")
                    return iconURL
                }
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
        
        // Set app identification metadata
        plist["CFBundleIconFile"] = "droplet.icns"
        plist["CFBundleName"] = (plist["CFBundleName"] as? String) ?? "MrHEVC Droplet"

        // Register supported file types so Finder allows drag & drop of movies onto the droplet
        let movieUTIs = [
            "public.movie",
            "com.apple.quicktime-movie",
            "public.mpeg-4",
            "public.mpeg-4-audio"
        ]

        let movieExtensions = ["mov", "mp4", "m4v", "mpg", "mpeg"]

        let documentType: [String: Any] = [
            "CFBundleTypeName": "Movie File",
            "CFBundleTypeRole": "Viewer",
            "LSItemContentTypes": movieUTIs,
            "CFBundleTypeExtensions": movieExtensions
        ]
        plist["CFBundleDocumentTypes"] = [documentType]

        // Hide the droplet from Dock/menu bar when launched
        plist["LSUIElement"] = true

        // Write back to plist
        let updatedData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try updatedData.write(to: infoPlistURL)

        print("✅ Updated droplet Info.plist with metadata and document types")
    }
    
    private func setFileIcon(dropletURL: URL, iconURL: URL) throws {
        // Use NSWorkspace to set the file icon
        let workspace = NSWorkspace.shared
        
        if let image = NSImage(contentsOf: iconURL) {
            workspace.setIcon(image, forFile: dropletURL.path, options: [])
            print("✅ Set droplet file icon programmatically")
        }
    }
    
    private func setIconProgrammatically(at dropletURL: URL, settings: Settings) throws {
        let workspace = NSWorkspace.shared
        
        // Determine which icon to use based on run mode
        let iconBaseName = (settings.runMode == .remoteDeadline) ? "DropletIconRemote" : "DropletIcon"
        
        // Try to get the mode-specific icon from Assets first
        if let customIcon = NSImage(named: iconBaseName) {
            workspace.setIcon(customIcon, forFile: dropletURL.path, options: [])
            print("✅ Set \(iconBaseName) from Assets programmatically")
            return
        }
        
        // Try with .icns extension in case that's how it's named
        if let customIcon = NSImage(named: "\(iconBaseName).icns") {
            workspace.setIcon(customIcon, forFile: dropletURL.path, options: [])
            print("✅ Set \(iconBaseName).icns from Assets programmatically")
            return
        }
        
        // Try with .icon extension
        if let customIcon = NSImage(named: "\(iconBaseName).icon") {
            workspace.setIcon(customIcon, forFile: dropletURL.path, options: [])
            print("✅ Set \(iconBaseName).icon from Assets programmatically")
            return
        }
        
        // Try to find custom icon file
        if let customIconURL = findDropletIcon(for: settings),
           let customIcon = NSImage(contentsOf: customIconURL) {
            workspace.setIcon(customIcon, forFile: dropletURL.path, options: [])
            print("✅ Set \(iconBaseName) from file programmatically")
            return
        }
        
        // Fallback: Try generic DropletIcon if we were looking for a specific one
        if iconBaseName != "DropletIcon" {
            if let fallbackIcon = NSImage(named: "DropletIcon") {
                workspace.setIcon(fallbackIcon, forFile: dropletURL.path, options: [])
                print("✅ Set fallback DropletIcon from Assets programmatically")
                return
            }
            
            if let fallbackIcon = NSImage(named: "DropletIcon.icon") {
                workspace.setIcon(fallbackIcon, forFile: dropletURL.path, options: [])
                print("✅ Set fallback DropletIcon.icon from Assets programmatically")
                return
            }
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
            throw DropletBuilderError.fileSystemError("Could not set droplet icon")
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

enum DropletBuilderError: LocalizedError {
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
