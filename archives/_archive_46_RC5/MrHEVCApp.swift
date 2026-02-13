// MrHEVCApp.swift — Complete file with CLI support + existing functionality
// Replace the entire MrHEVCApp.swift file with this content

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Carbon

@main
struct MrHEVCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    init() {
        // Check if we should run in CLI mode
        if shouldRunInCLIMode() {
            runCLIMode()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup(" ") {
            ContentView()
                .environmentObject(appState)
                .task {
                    if !appState.didBootstrapDeadline {
                        appState.bootstrapDeadlineLists()
                        NSLog("MrHEVC: bootstrapDeadlineLists() ran")
                    }
                }
                .onAppear {
                    AppState.shared = appState
                    FileDropHandler.shared.setAppState(appState)
                    appState.settings.coerceDropdownDefaultsTopFirst()
                    
                    // Only handle droplet mode if we're in GUI mode
                    handleDropletMode()
                }
        }
        .defaultSize(width: 700, height: 900)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
    
    // MARK: - CLI Mode Detection and Execution
    
    private func shouldRunInCLIMode() -> Bool {
        let arguments = CommandLine.arguments
        return arguments.contains("--cli")
    }
    
    private func runCLIMode() {
        print("MrHEVC CLI Mode")
        
        let arguments = CommandLine.arguments
        
        // Handle droplet mode in CLI
        if let dropletIndex = arguments.firstIndex(of: "--droplet"),
           dropletIndex + 1 < arguments.count {
            
            let dropletFilePath = arguments[dropletIndex + 1]
            let videoFilePaths = Array(arguments[(dropletIndex + 2)...]).filter { !$0.hasPrefix("--") }
            
            runDropletCLI(dropletFile: dropletFilePath, videoFiles: videoFilePaths)
            return
        }
        
        // Handle help
        if arguments.contains("--help") || arguments.contains("-h") {
            printCLIHelp()
            return
        }
        
        print("Error: No valid CLI command found. Use --help for usage information.")
        exit(1)
    }
    
    private func runDropletCLI(dropletFile: String, videoFiles: [String]) {
        print("Running droplet: \(dropletFile)")
        print("Video files: \(videoFiles)")
        
        // Load droplet settings
        guard let dropletData = try? Data(contentsOf: URL(fileURLWithPath: dropletFile)),
              let droplet = try? JSONDecoder().decode(DropletFile.self, from: dropletData) else {
            print("Error: Could not load droplet file: \(dropletFile)")
            
            showCLIErrorDialog(
                title: "Invalid Droplet",
                message: "Could not load droplet settings",
                detail: "The droplet file appears to be corrupted or from an incompatible version of MrHEVC.\n\nDroplet file: \(dropletFile)"
            )
            exit(1)
        }
        
        print("Loaded preset: \(droplet.presetName)")
        
        // Filter for .mov files
        let movFiles = videoFiles.filter { URL(fileURLWithPath: $0).pathExtension.lowercased() == "mov" }
        let nonMovFiles = videoFiles.filter { URL(fileURLWithPath: $0).pathExtension.lowercased() != "mov" }
        
        // Warn about non-MOV files
        if !nonMovFiles.isEmpty {
            let fileList = nonMovFiles.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            showCLIErrorDialog(
                title: "Unsupported Files",
                message: "Some files were skipped",
                detail: "Only QuickTime (.mov) files are supported.\n\nSkipped files: \(fileList)"
            )
        }
        
        guard !movFiles.isEmpty else {
            print("Error: No .mov files found in arguments")
            
            let fileList = videoFiles.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            showCLIErrorDialog(
                title: "No Supported Files",
                message: "No QuickTime (.mov) files found",
                detail: "This droplet can only process QuickTime (.mov) files.\n\nFiles provided: \(fileList.isEmpty ? "None" : fileList)"
            )
            exit(1)
        }
        
        print("Processing \(movFiles.count) .mov file(s)...")
        
        // Process each file
        var successCount = 0
        var failureCount = 0
        var errors: [String] = []
        
        for (index, filePath) in movFiles.enumerated() {
            let fileURL = URL(fileURLWithPath: filePath)
            print("[\(index + 1)/\(movFiles.count)] Processing: \(fileURL.lastPathComponent)")
            
            let success = processSingleFileCLI(fileURL: fileURL, settings: droplet.settings)
            if success {
                successCount += 1
                print("  ✅ Complete")
            } else {
                failureCount += 1
                errors.append(fileURL.lastPathComponent)
                print("  ❌ Failed")
            }
        }
        
        // Show final summary
        print("\nDroplet processing complete.")
        print("✅ Successful: \(successCount)")
        print("❌ Failed: \(failureCount)")
        
        if failureCount > 0 {
            let errorSummary = "Processing completed with some failures.\n\n✅ Successful: \(successCount) files\n❌ Failed: \(failureCount) files\n\nFailed files: \(errors.joined(separator: ", "))"
            
            showCLIErrorDialog(
                title: "Processing Complete with Errors",
                message: "Some files could not be processed",
                detail: errorSummary
            )
        } else if successCount > 0 {
            // Show success dialog
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Processing Complete"
                alert.informativeText = "Successfully processed \(successCount) file\(successCount == 1 ? "" : "s") using the '\(droplet.presetName)' preset."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
                NSApp.setActivationPolicy(.accessory)
            }
        }
        
        exit(failureCount > 0 ? 1 : 0)
    }
    
    private func processSingleFileCLI(fileURL: URL, settings: Settings) -> Bool {
        // Extract metadata
        let meta = MetadataExtractor.extract(for: fileURL)
        
        // Create media item
        let item = MediaItem(url: fileURL, meta: meta, status: .queued)
        
        // Determine output path
        let outputURL = OutputNamer.suggestedOutputURL(for: fileURL, settings: settings)
        
        // Pre-flight validation
        let validationResult = validateFileForProcessing(item: item, settings: settings)
        if !validationResult.isValid {
            print("  ❌ Validation failed: \(validationResult.reason)")
            showCLIErrorDialog(
                title: "File Validation Error",
                message: "Cannot process \(fileURL.lastPathComponent)",
                detail: validationResult.reason
            )
            return false
        }
        
        // Choose encoding method based on settings
        switch settings.runMode {
        case .localFFmpeg:
            return runLocalEncodeCLI(item: item, output: outputURL, settings: settings)
        case .remoteDeadline:
            return runRemoteEncodeCLI(item: item, output: outputURL, settings: settings)
        }
    }
    
    // MARK: - Validation
    
    private func validateFileForProcessing(item: MediaItem, settings: Settings) -> (isValid: Bool, reason: String) {
        // Check if file exists and is readable
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            return (false, "File does not exist or is not accessible.")
        }
        
        guard FileManager.default.isReadableFile(atPath: item.url.path) else {
            return (false, "File exists but cannot be read. Check file permissions.")
        }
        
        // Check file format
        let ext = item.url.pathExtension.lowercased()
        guard ext == "mov" else {
            return (false, "Only QuickTime (.mov) files are supported. Found: .\(ext)")
        }
        
        // Check for Remote mode specific requirements
        if settings.runMode == .remoteDeadline {
            let pathCheck = EncodeRemote.isInputPathAcceptableForFarm(item.url)
            if !pathCheck.ok {
                let reason = pathCheck.reason ?? "Path not accessible to render farm"
                return (false, "Remote encoding error: \(reason)\n\nFor Deadline rendering, files must be on shared network storage (e.g., /Volumes/Share/...), not local folders like Desktop or Downloads.")
            }
            
            // Check if Deadline settings are valid
            let poolCheck = settings.pool.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let groupCheck = settings.group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            if poolCheck.isEmpty || poolCheck == "none" {
                return (false, "Remote encoding error: Deadline pool is not configured.\n\nThis droplet was created for Deadline rendering but the pool setting is missing or set to 'none'.")
            }
            
            if groupCheck.isEmpty || groupCheck == "none" {
                return (false, "Remote encoding error: Deadline group is not configured.\n\nThis droplet was created for Deadline rendering but the group setting is missing or set to 'none'.")
            }
        }
        
        // Check for Local mode specific requirements
        if settings.runMode == .localFFmpeg {
            let ffmpegPath = findFFmpegPath()
            guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else {
                return (false, "Local encoding error: FFmpeg not found.\n\nThis droplet requires FFmpeg to be installed. Please install FFmpeg via Homebrew:\n\nbrew install ffmpeg")
            }
        }
        
        // Check if settings would result in no-op
        let compressionInactive = settings.bypassHEVC &&
                                 settings.scale == .oneToOne &&
                                 settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        let nclcInactive = settings.nclcTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no change" &&
                          settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        let overlaysInactive = !(settings.burnInFrames || settings.burnInTimecode || settings.burnInFilename)
        
        if compressionInactive && nclcInactive && overlaysInactive {
            return (false, "Configuration error: No processing operations are enabled.\n\nThis droplet is configured to bypass compression, skip color tagging, and has no overlays enabled. Nothing would be changed.")
        }
        
        // Check for potential filename conflicts
        let allSuffixesBlank = settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                               settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                               settings.scaleSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        if allSuffixesBlank {
            return (false, "Configuration error: Output filename would be identical to input.\n\nThis droplet has no filename suffixes configured, so the output would overwrite the original file.")
        }
        
        return (true, "")
    }
    
    // MARK: - Error Display
    
    private func showCLIErrorDialog(title: String, message: String, detail: String) {
        // For CLI mode, we need to show dialogs since there's no GUI
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = "\(message)\n\n\(detail)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            
            // For CLI mode, we need to make sure the app can show dialogs
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
            alert.runModal()
            
            // Return to background mode
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    private func runLocalEncodeCLI(item: MediaItem, output: URL, settings: Settings) -> Bool {
        let args = FFmpegCommandBuilder.buildArgs(item: item, output: output, settings: settings)
        
        // Find ffmpeg
        let ffmpegPath = findFFmpegPath()
        
        print("  Running ffmpeg...")
        
        // Create and run process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = Array(args.dropFirst()) // Remove executable name
        
        // Capture stderr for error reporting
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                return true
            } else {
                // Get error output from ffmpeg
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown ffmpeg error"
                
                let errorDetail = "FFmpeg failed with exit code \(process.terminationStatus).\n\nFFmpeg output:\n\(errorOutput.prefix(500))"
                
                showCLIErrorDialog(
                    title: "Encoding Failed",
                    message: "Local encoding failed for \(item.url.lastPathComponent)",
                    detail: errorDetail
                )
                return false
            }
        } catch {
            showCLIErrorDialog(
                title: "Encoding Failed",
                message: "Could not start FFmpeg",
                detail: "Error launching FFmpeg: \(error.localizedDescription)\n\nMake sure FFmpeg is installed:\nbrew install ffmpeg"
            )
            return false
        }
    }
    
    private func runRemoteEncodeCLI(item: MediaItem, output: URL, settings: Settings) -> Bool {
        // Submit to Deadline
        let deadlineCmd = settings.deadlineCommandPath.isEmpty
            ? (EncodeRemote.detectDeadlineCommand() ?? "/Applications/Thinkbox/Deadline10/Resources/deadlinecommand")
            : settings.deadlineCommandPath
        
        // Check if Deadline command exists
        guard FileManager.default.isExecutableFile(atPath: deadlineCmd) else {
            showCLIErrorDialog(
                title: "Deadline Not Found",
                message: "Cannot submit to Deadline",
                detail: "Deadline command not found at: \(deadlineCmd)\n\nThis droplet was created for Deadline rendering, but Deadline is not installed or not accessible on this machine."
            )
            return false
        }
        
        print("  Submitting to Deadline...")
        
        let result = EncodeRemote.submitFFmpegJob(
            deadlineCmd: deadlineCmd,
            item: item,
            settings: settings,
            ffmpegPath: "/usr/local/bin/ffmpeg"
        )
        
        if result.exitCode == 0 {
            if let jobID = extractJobID(from: result.rawOutput) {
                print("  Submitted as job: \(jobID)")
                
                // Show success dialog for remote submissions
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Deadline Submission Successful"
                    alert.informativeText = "File: \(item.url.lastPathComponent)\nJob ID: \(jobID)\n\nThe job has been submitted to the Deadline render farm."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            return true
        } else {
            let errorDetail = "Deadline submission failed with exit code \(result.exitCode).\n\nDeadline output:\n\(result.rawOutput.prefix(500))"
            
            showCLIErrorDialog(
                title: "Deadline Submission Failed",
                message: "Remote submission failed for \(item.url.lastPathComponent)",
                detail: errorDetail
            )
            return false
        }
    }
    
    private func findFFmpegPath() -> String {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg"
        ]
        
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // Try PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = path, !path.isEmpty {
                    return path
                }
            }
        } catch {}
        
        return "ffmpeg" // Hope it's in PATH
    }
    
    private func extractJobID(from output: String) -> String? {
        // Extract job ID from Deadline output
        if let match = output.range(of: #"\[([0-9a-f]{24})\]"#, options: .regularExpression) {
            return String(output[match]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        return nil
    }
    
    private func printCLIHelp() {
        print("""
        MrHEVC Command Line Interface
        
        Usage:
          MrHEVC --cli --droplet <preset.json> <file1.mov> [file2.mov] ...
          MrHEVC --help
        
        Options:
          --cli                 Run in CLI mode (no GUI)
          --droplet <file>      Use droplet preset file
          --help, -h            Show this help message
        
        Examples:
          # Process files with a droplet preset
          MrHEVC --cli --droplet MyPreset.json video1.mov video2.mov
          
          # For GUI droplet mode (current behavior)
          MrHEVC --droplet MyPreset.json video1.mov video2.mov
        """)
    }
    
    // MARK: - GUI Droplet Mode (existing functionality)
    
    private func handleDropletMode() {
        let arguments = CommandLine.arguments
        
        // Only handle GUI droplet mode (no --cli flag)
        guard !arguments.contains("--cli") else { return }
        
        guard let dropletIndex = arguments.firstIndex(of: "--droplet"),
              dropletIndex + 1 < arguments.count else {
            return // Not droplet mode
        }
        
        let dropletFilePath = arguments[dropletIndex + 1]
        let videoFilePaths = Array(arguments[(dropletIndex + 2)...])
        
        NSLog("MrHEVC: GUI Droplet mode detected - preset: \(dropletFilePath), files: \(videoFilePaths)")
        
        // Load droplet settings
        do {
            let dropletURL = URL(fileURLWithPath: dropletFilePath)
            let dropletData = try Data(contentsOf: dropletURL)
            let dropletFile = try JSONDecoder().decode(DropletFile.self, from: dropletData)
            
            // Enter droplet mode
            AppState.shared?.enableDropletMode(presetName: dropletFile.presetName, exitWhenDone: true)

            // Add video files to queue
            let videoURLs = videoFilePaths.compactMap { path in
                let url = URL(fileURLWithPath: path)
                return url.pathExtension.lowercased() == "mov" ? url : nil
            }
            
            if !videoURLs.isEmpty {
                appState.addFiles(videoURLs)
                
                // Auto-start encoding after UI is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let readyToEncode = self.appState.files.contains { $0.status == .queued && $0.isChecked }
                    if readyToEncode {
                        self.appState.submit()
                    }
                }
            }
            
        } catch {
            NSLog("MrHEVC: Failed to load droplet: \(error)")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Droplet Error"
                alert.informativeText = "Could not load droplet settings: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

// MARK: - File Drop Handler (existing code, kept as-is)

final class FileDropHandler: NSObject {
    static let shared = FileDropHandler()

    private weak var appState: AppState?
    private var pending: [URL] = []

    override init() {
        super.init()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenDocuments(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID:    AEEventID(kAEOpenDocuments)
        )
        NSLog("MrHEVC: File drop handler installed")
    }

    func setAppState(_ state: AppState) {
        self.appState = state
        if !pending.isEmpty {
            let urls = pending
            pending.removeAll()
            processURLs(urls, into: state)
            NSLog("MrHEVC: flushed \(urls.count) buffered url(s)")
        }
    }

    @objc private func handleOpenDocuments(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        NSLog("MrHEVC: handleOpenDocuments called")
        let urls = extractFileURLs(from: event)
        
        if let state = appState {
            processURLs(urls, into: state)
        } else {
            pending.append(contentsOf: urls)
            NSLog("MrHEVC: buffered \(urls.count) url(s) (state not ready)")
        }
    }

    private func processURLs(_ urls: [URL], into state: AppState) {
        var dropletFiles: [URL] = []
        var videoFiles: [URL] = []
        
        for url in urls {
            if url.pathExtension.lowercased() == "mrhevc" {
                dropletFiles.append(url)
            } else if isAllowedQuickTime(url) {
                videoFiles.append(url)
            }
        }
        
        DispatchQueue.main.async {
            if let dropletURL = dropletFiles.first {
                self.handleDropletFile(dropletURL, into: state)
            }
            
            if !videoFiles.isEmpty {
                self.enqueueVideoFiles(videoFiles, into: state)
            }

            if let key = NSApp.keyWindow { key.orderFrontRegardless() }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func handleDropletFile(_ url: URL, into state: AppState) {
        do {
            let dropletFile = try PresetManager.shared.loadDroplet(from: url)
            state.enableDropletMode(presetName: dropletFile.presetName, exitWhenDone: true)
            NSLog("MrHEVC: Loaded droplet: \(dropletFile.presetName)")
        } catch {
            NSLog("MrHEVC: Failed to load droplet: \(error)")
            
            let alert = NSAlert()
            alert.messageText = "Invalid Droplet File"
            alert.informativeText = "Could not load droplet file: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func enqueueVideoFiles(_ urls: [URL], into state: AppState) {
        NSLog("MrHEVC: Adding \(urls.count) video file(s) to queue")
        state.addFiles(urls)

        if state.settings.autoEncodeOnDrop,
           state.files.contains(where: { $0.status == .queued }) {
            NSLog("MrHEVC: Auto-Encode is ON → submitting")
            state.submit()
        } else {
            NSLog("MrHEVC: Auto-Encode is OFF → not submitting")
        }
    }

    private func extractFileURLs(from event: NSAppleEventDescriptor) -> [URL] {
        var urls: [URL] = []
        guard let direct = event.paramDescriptor(forKeyword: keyDirectObject) else {
            NSLog("MrHEVC: No direct object in Apple Event")
            return []
        }
        if direct.descriptorType == typeAEList {
            NSLog("MrHEVC: AE list with \(direct.numberOfItems) items")
            for i in 1...direct.numberOfItems {
                if let item = direct.atIndex(i), let u = item.fileURLFallback() { urls.append(u) }
            }
        } else if let u = direct.fileURLFallback() {
            NSLog("MrHEVC: Single AE item")
            urls.append(u)
        }
        NSLog("MrHEVC: Extracted \(urls.count) URL(s)")
        return urls
    }

    private func isAllowedQuickTime(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type == .quickTimeMovie || type.conforms(to: .quickTimeMovie)
        }
        return url.pathExtension.lowercased() == "mov"
    }
}

// File URL extraction helper (SDK-tolerant)
private extension NSAppleEventDescriptor {
    func fileURLFallback() -> URL? {
        if responds(to: NSSelectorFromString("fileURLValue")),
           let val = perform(NSSelectorFromString("fileURLValue"))?.takeUnretainedValue() as? URL {
            return val
        }
        if let path = stringValue, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        guard let coerced = coerce(toDescriptorType: typeFileURL) else { return nil }
        let data: Data = coerced.data
        if data.isEmpty { return nil }
        return data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            return (CFURLCreateWithBytes(
                kCFAllocatorDefault,
                base,
                rawBuf.count,
                CFStringBuiltInEncodings.UTF8.rawValue,
                nil
            ) as URL?)
        }
    }
}
