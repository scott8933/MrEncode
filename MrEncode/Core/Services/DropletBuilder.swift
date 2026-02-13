// =============================
// File: DropletBuilder.swift - Cleaned up version with preset resource embedding
// =============================

import Foundation
import AppKit

final class DropletBuilder {
    static let shared = DropletBuilder()

    private init() {}

    // MARK: - Constants

    /// Plain JSON droplet preset stored inside the droplet app bundle.
    /// (Finder droplet remains .app; this is the inspectable preset resource.)
    private static let presetResourceFilename = "Preset.mrepreset"

    // MARK: - Public Interface

    /// Create an AppleScript droplet application that will launch MrEncode with preset settings
    func createDroplet(presetName: String, settings: Settings, at outputURL: URL, extraCLIArgs: [String]) throws {
        // 1) Load and substitute template
        let scriptContent = try loadAndSubstituteTemplate(
            presetName: presetName,
            settings: settings,
            extraCLIArgs: extraCLIArgs
        )

        // 2) Create temporary .scpt file
        let tempDir = FileManager.default.temporaryDirectory
        let tempScriptURL = tempDir.appendingPathComponent("\(UUID().uuidString).scpt")
        try scriptContent.write(to: tempScriptURL, atomically: true, encoding: .utf8)

        // 3) Compile to application bundle
        try compileToApplication(scriptURL: tempScriptURL, outputURL: outputURL)

        // 4) Clean up temporary file
        try? FileManager.default.removeItem(at: tempScriptURL)

        // 5) Embed an inspectable preset resource into the droplet bundle
        try embedPresetResource(intoDropletAt: outputURL, presetName: presetName, settings: settings)
        
        // 6) Embed MrEncodeProgress.app (for progress UI)
        try embedProgressApp(intoDropletAt: outputURL)
        
        // 7) Set custom icon (don’t fail droplet build for icon issues)
        do {
            try setDropletIcon(at: outputURL)
        } catch {
            print("⚠️ Could not set droplet icon: \(error)")
        }

        // 8) Set additional metadata
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

        // Accessory checkboxes (persisted)
        let prefs = PreferencesService.shared

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 54))

        let chkPopup = NSButton(checkboxWithTitle: "Show completion popup", target: nil, action: nil)
        chkPopup.state = prefs.dropletExportShowPopup ? .on : .off
        chkPopup.frame = NSRect(x: 0, y: 28, width: 360, height: 20)

        let chkChime = NSButton(checkboxWithTitle: "Play finish chime", target: nil, action: nil)
        chkChime.state = prefs.dropletExportPlayChime ? .on : .off
        chkChime.frame = NSRect(x: 0, y: 4, width: 360, height: 20)

        accessory.addSubview(chkPopup)
        accessory.addSubview(chkChime)
        panel.accessoryView = accessory

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(false)
                return
            }

            let prefs = PreferencesService.shared

            let showPopup = (chkPopup.state == .on)
            let playChime = (chkChime.state == .on)

            // Persist
            prefs.dropletExportShowPopup = showPopup
            prefs.dropletExportPlayChime = playChime

            // Translate to embedded CLI flags
            var extraCLIArgs: [String] = []
            if !showPopup { extraCLIArgs.append("--quiet") }
            if !playChime { extraCLIArgs.append("--mute") }

            do {
                try self.createDroplet(
                    presetName: presetName,
                    settings: settings,
                    at: url,
                    extraCLIArgs: extraCLIArgs
                )
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

    private func loadAndSubstituteTemplate(presetName: String, settings: Settings, extraCLIArgs: [String]) throws -> String {
        // 1) Try multiple ways to find the template
        var templateURL: URL?

        templateURL = Bundle.main.url(forResource: "DropletScript.applescript", withExtension: "template")

        if templateURL == nil {
            templateURL = Bundle.main.url(forResource: "DropletScript", withExtension: "txt")
        }

        if templateURL == nil {
            templateURL = Bundle.main.url(forResource: "DropletScript", withExtension: "applescript")
        }

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

        // 2) Encode settings as JSON (DropletFile JSON)
        //    Back-compat: template may still embed it as a string.
        let settingsJSON = try encodeDropletFileAsJSON(settings, presetName: presetName)

        // 3) Get bundle ID
        let bundleID = Bundle.main.bundleIdentifier ?? "com.grayrobot.mrencode"

        // 4) Get creation date
        let creationDate = DateFormatter.dropletTimestamp.string(from: Date())

        // 5) Escape values for AppleScript
        let escapedPresetName = escapeForAppleScript(presetName)
        let escapedSettingsJSON = escapeForAppleScript(settingsJSON)
        let escapedBundleID = escapeForAppleScript(bundleID)
        let escapedCreationDate = escapeForAppleScript(creationDate)

        let extraArgsString = extraCLIArgs.joined(separator: " ")
        let escapedExtraArgs = escapeForAppleScript(extraArgsString)

        // New: expose the resource filename to the script template.
        let escapedPresetResourceName = escapeForAppleScript(Self.presetResourceFilename)

        // 6) Substitute placeholders
        let substitutions: [String: String] = [
            "{{PRESET_NAME}}": escapedPresetName,
            "{{SETTINGS_JSON}}": escapedSettingsJSON,                 // back-compat
            "{{PRESET_RESOURCE_NAME}}": escapedPresetResourceName,    // new
            "{{BUNDLE_ID}}": escapedBundleID,
            "{{CREATION_DATE}}": escapedCreationDate,
            "{{APP_PATH}}": escapeForAppleScript(Bundle.main.bundlePath),
            "{{CLI_EXTRA_ARGS}}": escapedExtraArgs
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

    /// Returns DropletFile JSON as a string (used for back-compat AppleScript templates).
    private func encodeDropletFileAsJSON(_ settings: Settings, presetName: String) throws -> String {
        let dropletFile = DropletFile(presetName: presetName, settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [] // compact
        let data = try encoder.encode(dropletFile)

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw DropletBuilderError.encodingFailed
        }
        return jsonString
    }

    // MARK: - Embed preset resource into droplet bundle

    private func embedPresetResource(intoDropletAt dropletURL: URL, presetName: String, settings: Settings) throws {
        let fm = FileManager.default
        let resourcesURL = dropletURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true, attributes: nil)

        let outURL = resourcesURL.appendingPathComponent(Self.presetResourceFilename, isDirectory: false)

        let dropletFile = DropletFile(presetName: presetName, settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dropletFile)

        if fm.fileExists(atPath: outURL.path) {
            try? fm.removeItem(at: outURL)
        }

        try data.write(to: outURL, options: [.atomic])
        print("✅ Embedded preset resource: \(outURL.lastPathComponent)")
    }
    

    /// Embed MrEncodeProgress.app into the droplet's Resources folder
    private func embedProgressApp(intoDropletAt dropletURL: URL) throws {
        let fm = FileManager.default
        
        // Find MrEncodeProgress.app in our app bundle
        guard let progressAppURL = Bundle.main.url(forResource: "MrEncodeProgress", withExtension: "app") else {
            print("⚠️ MrEncodeProgress.app not found in bundle - droplet will run without progress UI")
            return
        }
        
        // Create Resources directory if needed
        let resourcesURL = dropletURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true, attributes: nil)
        
        // Copy MrEncodeProgress.app into droplet's Resources
        let destURL = resourcesURL.appendingPathComponent("MrEncodeProgress.app", isDirectory: true)
        
        // Remove if already exists
        if fm.fileExists(atPath: destURL.path) {
            try? fm.removeItem(at: destURL)
        }
        
        try fm.copyItem(at: progressAppURL, to: destURL)
        print("✅ Embedded MrEncodeProgress.app into droplet")
    }

    // MARK: - Compilation

    private func compileToApplication(scriptURL: URL, outputURL: URL) throws {
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

    // MARK: - Icon Handling (unchanged)

    private func setDropletIcon(at dropletURL: URL) throws {
        let fm = FileManager.default
        let dropletResourcesURL = dropletURL.appendingPathComponent("Contents/Resources")

        try fm.createDirectory(at: dropletResourcesURL, withIntermediateDirectories: true)

        var iconWasSet = false

        if let iconURL = findDropletIconFile(), iconURL.pathExtension.lowercased() == "icns" {
            let dropletIconURL = dropletResourcesURL.appendingPathComponent("droplet.icns")

            do {
                try? fm.removeItem(at: dropletIconURL)
                try fm.copyItem(at: iconURL, to: dropletIconURL)
                print("✅ Copied droplet.icns to bundle")
                iconWasSet = true
            } catch {
                print("⚠️ Failed to copy .icns file: \(error)")
            }
        }

        if !iconWasSet, let icon = findDropletIcon() {
            let dropletIconURL = dropletResourcesURL.appendingPathComponent("droplet.icns")

            do {
                try saveAsICNS(image: icon, to: dropletIconURL)
                print("✅ Created droplet.icns from NSImage")
                iconWasSet = true
            } catch {
                print("⚠️ Failed to create .icns from image: \(error)")
            }
        }

        try updateDropletInfoPlist(at: dropletURL)

        if let icon = findDropletIcon() {
            NSWorkspace.shared.setIcon(icon, forFile: dropletURL.path, options: [])
            print("✅ Set icon on droplet bundle")
        }

        if !iconWasSet {
            print("⚠️ Warning: No icon was embedded in droplet bundle")
        }
    }

    private func findDropletIconFile() -> URL? {
        let bundle = Bundle.main

        print("🔍 Looking for droplet icon...")

        if let iconURL = bundle.url(forResource: "DropletIcon", withExtension: "icns") {
            print("✅ Found DropletIcon.icns in bundle")
            return iconURL
        }

        if let iconURL = bundle.url(forResource: "MrEncode_Droplet", withExtension: "icns") {
            print("✅ Found MrEncode_Droplet.icns in bundle")
            return iconURL
        }

        print("⚠️ No .icns file found in bundle")
        return nil
    }

    private func findDropletIcon() -> NSImage? {
        if let icon = NSImage(named: "MrEncode_Droplet") {
            print("✅ Found MrEncode_Droplet in Assets catalog")
            return icon
        }

        if let icon = NSImage(named: "DropletIcon") {
            print("✅ Found DropletIcon in Assets catalog")
            return icon
        }

        if let iconURL = findDropletIconFile(),
           let icon = NSImage(contentsOf: iconURL) {
            print("✅ Loaded droplet icon from file")
            return icon
        }

        if let appIcon = NSImage(named: "AppIcon") {
            print("✅ Using main AppIcon as fallback")
            return appIcon
        }

        let mainAppURL = Bundle.main.bundleURL
        let appIcon = NSWorkspace.shared.icon(forFile: mainAppURL.path)
        print("✅ Using app bundle icon as final fallback")
        return appIcon
    }

    private func updateDropletInfoPlist(at dropletURL: URL) throws {
        let infoPlistURL = dropletURL.appendingPathComponent("Contents/Info.plist")

        guard let plistData = try? Data(contentsOf: infoPlistURL),
              var plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            print("⚠️ Could not read droplet Info.plist")
            return
        }

        plist["CFBundleIconFile"] = "droplet"
        plist["CFBundleIconName"] = "droplet"
        plist["CFBundleName"] = (plist["CFBundleName"] as? String) ?? "MrEncode Droplet"
        plist["LSUIElement"] = true
        plist.removeValue(forKey: "NSUIElement")

        let movieUTIs = [
            "public.movie",
            "com.apple.quicktime-movie",
            "public.mpeg-4",
            "public.mpeg-4-audio",
            "public.image.gif"
        ]

        let movieExtensions = ["mov", "mp4", "m4v", "mpg", "mpeg", "gif"]

        let documentType: [String: Any] = [
            "CFBundleTypeName": "Movie File",
            "CFBundleTypeRole": "Viewer",
            "LSItemContentTypes": movieUTIs,
            "CFBundleTypeExtensions": movieExtensions
        ]

        let folderType: [String: Any] = [
            "CFBundleTypeName": "Folder",
            "CFBundleTypeRole": "Viewer",
            "LSItemContentTypes": ["public.folder", "public.directory"]
        ]

        plist["CFBundleDocumentTypes"] = [documentType, folderType]

        let updatedData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try updatedData.write(to: infoPlistURL)

        print("✅ Updated droplet Info.plist")
    }

    private func saveAsICNS(image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            throw DropletBuilderError.fileSystemError("Could not get image representation")
        }

        let tempDir = FileManager.default.temporaryDirectory
        let iconsetURL = tempDir.appendingPathComponent("temp_\(UUID().uuidString).iconset")

        do {
            try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

            let sizes: [(String, Int)] = [
                ("icon_16x16.png", 16),
                ("icon_16x16@2x.png", 32),
                ("icon_32x32.png", 32),
                ("icon_32x32@2x.png", 64),
                ("icon_128x128.png", 128),
                ("icon_128x128@2x.png", 256),
                ("icon_256x256.png", 256),
                ("icon_256x256@2x.png", 512),
                ("icon_512x512.png", 512),
                ("icon_512x512@2x.png", 1024)
            ]

            for (filename, size) in sizes {
                let resized = image.resized(to: NSSize(width: size, height: size))
                if let pngData = resized?.pngData() {
                    let pngURL = iconsetURL.appendingPathComponent(filename)
                    try pngData.write(to: pngURL)
                }
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
            process.arguments = ["-c", "icns", iconsetURL.path, "-o", url.path]

            try process.run()
            process.waitUntilExit()

            try? FileManager.default.removeItem(at: iconsetURL)

            if process.terminationStatus == 0 {
                print("✅ Successfully created .icns file using iconutil")
                return
            } else {
                print("⚠️ iconutil failed, falling back to PNG")
            }
        } catch {
            print("⚠️ Could not create iconset: \(error)")
        }

        if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try pngData.write(to: url)
            print("⚠️ Saved icon as PNG (not ideal for droplets)")
        } else {
            throw DropletBuilderError.fileSystemError("Could not save icon")
        }
    }

    private func setDropletMetadata(at dropletURL: URL, presetName: String) throws {
        do {
            let displayName = "\(presetName) Droplet"
            let xattrKey = "com.apple.metadata:kMDItemDisplayName"
            let xattrValue = displayName.data(using: .utf8) ?? Data()

            _ = setxattr(dropletURL.path, xattrKey, xattrValue.withUnsafeBytes { $0.baseAddress }, xattrValue.count, 0, 0)
        } catch {
            print("⚠️ Could not set droplet metadata: \(error)")
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

// MARK: - NSImage Extensions
private extension NSImage {
    func resized(to newSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        defer { newImage.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)

        return newImage
    }

    func pngData() -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }
}
