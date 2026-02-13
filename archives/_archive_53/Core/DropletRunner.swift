//
//  DropletRunner.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/19/25.
//


import Foundation
import AppKit

/// Handles CLI droplet execution and shared droplet validation logic.
struct DropletRunner {
    static func run(arguments: [String]) -> Int {
        // Centralized flag parsing (single source of truth)
        let flags = RuntimeFlags.parse(arguments)
        let quiet = flags.quiet
        let suppressChime = flags.suppressChime

        // Handle help
        if arguments.contains("--help") || arguments.contains("-h") {
            printCLIHelp()
            return 0
        }

        // Handle droplet CLI (supports both legacy --preset-file and new --droplet flags)
        if let result = parsePathArgument(arguments, flag: "--preset-file") {
            let videoFilePaths = collectMediaPaths(from: arguments, startingAt: result.nextIndex)
            return runDropletCLI(dropletFile: result.path, videoFiles: videoFilePaths, quiet: quiet, suppressChime: suppressChime)
        }

        if let result = parsePathArgument(arguments, flag: "--droplet") {
            let videoFilePaths = collectMediaPaths(from: arguments, startingAt: result.nextIndex)
            return runDropletCLI(dropletFile: result.path, videoFiles: videoFilePaths, quiet: quiet, suppressChime: suppressChime)
        }

        print("Error: No valid CLI command found. Use --help for usage information.")
        return 1
    }


    // MARK: - Droplet CLI
    
    private static func ensureAppKitInitialized() {
        _ = NSApplication.shared
    }

    private static func fireDoneChimeIfAllowed(suppressChime: Bool) {
        guard !suppressChime else { return }
        Task { @MainActor in
            SoundManager.shared.playDoneChime()
        }
    }

    /// Gives the main runloop a brief chance to execute scheduled @MainActor work.
    /// Use this only for the "quiet + chime-only" case.
    private static func pumpMainRunLoop(seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        RunLoop.main.run(until: until)
    }


    private static func runDropletCLI(dropletFile: String, videoFiles: [String], quiet: Bool, suppressChime: Bool) -> Int {
        print("Running droplet: \(dropletFile)")
        print("Video files: \(videoFiles)")

        // Load droplet settings
        guard let dropletData = try? Data(contentsOf: URL(fileURLWithPath: dropletFile)),
              let droplet = try? JSONDecoder().decode(DropletFile.self, from: dropletData) else {
            print("Error: Could not load droplet file: \(dropletFile)")

            showCLIErrorDialog(
                title: "Invalid Droplet",
                message: "Could not load droplet settings",
                detail: "The droplet file appears to be corrupted or from an incompatible version of MrEncode.\n\nDroplet file: \(dropletFile)",
                quiet: quiet
            )
            return 1
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
                detail: "Only QuickTime (.mov) files are supported.\n\nSkipped files: \(fileList)",
                quiet: quiet
            )
        }

        guard !movFiles.isEmpty else {
            print("Error: No .mov files found in arguments")

            let fileList = videoFiles.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            showCLIErrorDialog(
                title: "No Supported Files",
                message: "No QuickTime (.mov) files found",
                detail: "This droplet can only process QuickTime (.mov) files.\n\nFiles provided: \(fileList.isEmpty ? "None" : fileList)",
                quiet: quiet
            )
            return 1
        }

        print("Processing \(movFiles.count) .mov file(s)...")

        // Process each file
        var successCount = 0
        var failureCount = 0
        var errors: [(file: String, error: DropletError)] = []
        var submittedJobIDs: [String] = []
        var cancelCount = 0

        let fileURLs = movFiles.map { URL(fileURLWithPath: $0) }
        let results = processFiles(fileURLs, settings: droplet.settings) { _, jobID in
            guard !jobID.isEmpty else { return }
            submittedJobIDs.append(jobID)
            print("  Submitted as job: \(jobID)")
        }

        for (index, entry) in results.enumerated() {
            let fileURL = entry.url
            print("[\(index + 1)/\(results.count)] Processing: \(fileURL.lastPathComponent)")

            switch entry.result {
            case .success:
                successCount += 1
                print("  Complete")
            case .failure(let error):
                if case .cancelled = error {
                    cancelCount += 1
                    print("  Cancelled by user")
                } else {
                    failureCount += 1
                    errors.append((fileURL.lastPathComponent, error))
                    print("  Failed")
                    presentCLI(error: error, fileName: fileURL.lastPathComponent, quiet: quiet)
                }
            }
        }

        // Show final summary
        DropletRunner.ensureAppKitInitialized()

        print("\nDroplet processing complete.")
        print("Successful: \(successCount)")
        print("Failed: \(failureCount)")

        if failureCount > 0 {
            let failedList = errors
                .map { "• \($0.file): \($0.error.message)" }
                .joined(separator: "\n")

            let errorSummary =
                "Processing completed with some failures.\n\n" +
                "Successful: \(successCount) file\(successCount == 1 ? "" : "s")\n" +
                "Failed: \(failureCount) file\(failureCount == 1 ? "" : "s")\n\n" +
                "Failed files:\n\(failedList)"

            // Chime at the same finish moment as the popup (or would-have-popup moment)
            DropletRunner.fireDoneChimeIfAllowed(suppressChime: suppressChime)

            if !quiet {
                showCLIErrorDialog(
                    title: "Processing Complete with Errors",
                    message: "Some files could not be processed",
                    detail: errorSummary,
                    quiet: quiet
                )
            } else if !suppressChime {
                // quiet + chime-only
                DropletRunner.pumpMainRunLoop(seconds: 0.35)
            }

        } else if successCount > 0 {

            DropletRunner.fireDoneChimeIfAllowed(suppressChime: suppressChime)

            if !quiet {
                let alert = NSAlert()
                alert.messageText = "Processing Complete"
                alert.informativeText =
                    "Successfully processed \(successCount) file\(successCount == 1 ? "" : "s") using the '\(droplet.presetName)' preset."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")

                let app = NSApplication.shared
                app.setActivationPolicy(.regular)
                app.activate(ignoringOtherApps: true)
                alert.runModal()
                app.setActivationPolicy(.accessory)

            } else if !suppressChime {
                // quiet + chime-only
                DropletRunner.pumpMainRunLoop(seconds: 0.35)
            }

        } else {
            // No supported files or nothing processed; earlier validation paths should have handled messaging.
            // Do not chime here.
        }

        return failureCount > 0 ? 1 : 0
    }

    /// Processes a single media file with the provided settings.
    /// Returns a `Result` so CLI and GUI wrappers can report failures differently and unit tests
    /// can cover each error scenario without depending on alerts.
    static func processFile(fileURL: URL,
                            settings: Settings,
                            jobIDSink: ((String) -> Void)? = nil) -> Result<Void, DropletError> {
        let meta = MetadataExtractor.extract(for: fileURL)
        let item = MediaItem(url: fileURL, meta: meta, status: .queued)
        let outputURL = OutputNamer.suggestedOutputURL(for: fileURL, settings: settings)

        switch validateFileForProcessing(item: item, settings: settings) {
        case .success:
            break
        case .failure(let error):
            return .failure(error)
        }

        switch settings.runMode {
        case .localFFmpeg:
            return runLocalEncodeCLI(item: item, output: outputURL, settings: settings)
        case .remoteDeadline:
            return runRemoteEncodeCLI(item: item, output: outputURL, settings: settings, jobIDSink: jobIDSink)
        }
    }

    /// Convenience batch helper used by CLI/GUI wrappers and unit tests.
    static func processFiles(_ fileURLs: [URL],
                             settings: Settings,
                             jobIDSink: ((URL, String) -> Void)? = nil) -> [(url: URL, result: Result<Void, DropletError>)] {
        fileURLs.map { url in
            let result = processFile(fileURL: url, settings: settings) { jobID in
                jobIDSink?(url, jobID)
            }
            return (url, result)
        }
    }
    
    
    // MARK: - Parsing Helpers
    
    private static func collectMediaPaths(from arguments: [String], startingAt index: Int) -> [String] {
        var paths: [String] = []
        var i = index

        while i < arguments.count {
            let arg = arguments[i]

            // Skip any flag that consumes the next argument (flag + value)
            if RuntimeFlags.flagsWithValue.contains(arg) {
                i += 2
                continue
            }

            // Skip any other flags (boolean switches, unknown flags, etc.)
            if arg.hasPrefix("-") {
                i += 1
                continue
            }

            // Positional argument -> treat as a candidate media path
            paths.append(arg)
            i += 1
        }

        return paths
    }


    // MARK: - Validation

    private static func validateFileForProcessing(item: MediaItem, settings: Settings) -> Result<Void, DropletError> {
        let url = item.url
        let ext = url.pathExtension.lowercased()

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.validation(message: "File does not exist or is not accessible."))
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .failure(.validation(message: "File exists but cannot be read. Check file permissions."))
        }

        guard ext == "mov" else {
            return .failure(.validation(message: "Only QuickTime (.mov) files are supported. Found: .\(ext)"))
        }

        if settings.runMode == .remoteDeadline {
            if case .failure(let error) = EncodeRemote.isInputPathAcceptableForFarm(url) {
                return .failure(.validation(message: "Remote encoding error: \(error.message)\n\nFor Deadline rendering, files must be on shared network storage (e.g., /Volumes/Share/...), not local folders like Desktop or Downloads."))
            }

            let pool = settings.pool.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let group = settings.group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if pool.isEmpty || pool == "none" {
                return .failure(.validation(message: "Remote encoding error: Deadline pool is not configured.\n\nThis droplet was created for Deadline rendering but the pool setting is missing or set to 'none'."))
            }

            if group.isEmpty || group == "none" {
                return .failure(.validation(message: "Remote encoding error: Deadline group is not configured.\n\nThis droplet was created for Deadline rendering but the group setting is missing or set to 'none'."))
            }
        }

        if settings.runMode == .localFFmpeg {
            let ffmpegPath = findFFmpegPath()
            guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else {
                return .failure(.validation(message: "Local encoding error: FFmpeg not found.\n\nThis droplet requires FFmpeg to be installed. Please install FFmpeg via Homebrew:\n\nbrew install ffmpeg"))
            }
        }

        let compressionInactive = settings.bypassHEVC &&
            settings.scale == .oneToOne &&
            settings.outputSuffix.trimmed.isEmpty

        let nclcInactive = settings.nclcTag.trimmed.lowercased() == "no change" &&
            settings.nclcFilenameLabel.trimmed.isEmpty

        let overlaysInactive = !(settings.burnInFrames || settings.burnInTimecode || settings.burnInFilename)

        if compressionInactive && nclcInactive && overlaysInactive {
            return .failure(.validation(message: "Configuration error: No processing operations are enabled.\n\nThis droplet is configured to bypass compression, skip color tagging, and has no overlays enabled. Nothing would be changed."))
        }

        let allSuffixesBlank = settings.outputSuffix.trimmed.isEmpty &&
            settings.nclcFilenameLabel.trimmed.isEmpty &&
            settings.scaleSuffix.trimmed.isEmpty

        if allSuffixesBlank {
            return .failure(.validation(message: "Configuration error: Output filename would be identical to input.\n\nThis droplet has no filename suffixes configured, so the output would overwrite the original file."))
        }

        return .success(())
    }

    // MARK: - Execution Helpers

    private static func runLocalEncodeCLI(item: MediaItem, output: URL, settings: Settings) -> Result<Void, DropletError> {
        let args = FFmpegCommandBuilder.buildArgs(item: item, output: output, settings: settings)
        let ffmpegPath = findFFmpegPath()

        print("  Running ffmpeg...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = Array(args.dropFirst())

        let errorPipe = Pipe()
        let outputPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = outputPipe

        let progressWindow = DropletProgressWindow()
        var wasCancelled = false

        progressWindow.show(fileName: item.url.lastPathComponent) {
            wasCancelled = true
            if process.isRunning {
                process.interrupt()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    if process.isRunning {
                        process.terminate()
                    }
                }
            }
        }

        let durationSeconds = item.meta.durationSeconds
        if durationSeconds > 0 {
            progressWindow.configureDeterminate(totalSeconds: durationSeconds)
            progressWindow.updateMessage("Processing \(item.url.lastPathComponent) — 0%")
        }

        let dataQueue = DispatchQueue(label: "droplet.ffmpeg.stderr.\(item.id)", qos: .utility)
        var stderrData = Data()
        var lastProgressUpdate = Date.distantPast
        let progressUpdateInterval: TimeInterval = 0.5

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            dataQueue.async {
                stderrData.append(data)

                if durationSeconds > 0,
                   Date().timeIntervalSince(lastProgressUpdate) >= progressUpdateInterval,
                   let chunk = String(data: data, encoding: .utf8),
                   let range = chunk.range(of: #"time=\d{2}:\d{2}:\d{2}\.\d{2}"#, options: .regularExpression) {
                    lastProgressUpdate = Date()
                    let token = String(chunk[range]).replacingOccurrences(of: "time=", with: "")
                    let elapsed = parseHHMMSS(token)
                    progressWindow.updateProgress(elapsedSeconds: elapsed)
                    let fraction = min(max(elapsed / durationSeconds, 0), 1)
                    let percentage = Int(fraction * 100)
                    progressWindow.updateMessage("Processing \(item.url.lastPathComponent) — \(percentage)%")
                }
            }
        }

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            outputPipe.fileHandleForReading.readabilityHandler = nil
            progressWindow.close()
            let detail = "Error launching FFmpeg: \(error.localizedDescription)\n\nMake sure FFmpeg is installed:\nbrew install ffmpeg"
            return .failure(.encodeFailed(message: detail))
        }

        let app = NSApplication.shared
        while process.isRunning {
            let deadline = Date(timeIntervalSinceNow: 0.1)
            if let event = app.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
                app.sendEvent(event)
            }
            app.updateWindows()
        }

        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputPipe.fileHandleForReading.readabilityHandler = nil
        dataQueue.sync { }
        let remainingErr = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingErr.isEmpty {
            stderrData.append(remainingErr)
        }

        progressWindow.close()

        if wasCancelled || process.terminationReason == .uncaughtSignal {
            return .failure(.cancelled(message: "Encoding cancelled by user."))
        }

        if process.terminationStatus == 0 {
            return .success(())
        } else {
            let errorOutput = String(data: stderrData, encoding: .utf8) ?? "Unknown ffmpeg error"
            let detail = "FFmpeg failed with exit code \(process.terminationStatus).\n\nFFmpeg output:\n\(errorOutput.prefix(500))"
            return .failure(.encodeFailed(message: detail))
        }
    }

    private static func runRemoteEncodeCLI(item: MediaItem,
                                           output: URL,
                                           settings: Settings,
                                           jobIDSink: ((String) -> Void)? = nil) -> Result<Void, DropletError> {
        let deadlineCmd = settings.deadlineCommandPath.isEmpty
            ? (EncodeRemote.detectDeadlineCommand() ?? "/Applications/Thinkbox/Deadline10/Resources/deadlinecommand")
            : settings.deadlineCommandPath

        guard FileManager.default.isExecutableFile(atPath: deadlineCmd) else {
            let detail = "Deadline command not found at: \(deadlineCmd)\n\nThis droplet was created for Deadline rendering, but Deadline is not installed or not accessible on this machine."
            return .failure(.deadlineFailed(message: detail))
        }

        print("  Submitting to Deadline...")

        let result = EncodeRemote.submitFFmpegJob(
            deadlineCmd: deadlineCmd,
            item: item,
            settings: settings,
            ffmpegPath: "/usr/local/bin/ffmpeg"
        )

        if result.exitCode == 0 {
            var jobID = result.jobID ?? extractJobID(from: result.rawOutput)
            if let extracted = jobID, !extracted.isEmpty {
                jobIDSink?(extracted)
            }
            return .success(())
        } else {
            let detail = "Deadline submission failed with exit code \(result.exitCode).\n\nDeadline output:\n\(result.rawOutput.prefix(500))"
            return .failure(.deadlineFailed(message: detail))
        }
    }

    // MARK: - Error Presentation

    private static func presentCLI(error: DropletError, fileName: String, quiet: Bool) {
        print("  \(error.title): \(error.message)")
        let message: String
        switch error {
        case .cancelled:
            message = "Cancelled: \(fileName)"
        default:
            message = "Cannot process \(fileName)"
        }
        showCLIErrorDialog(
            title: error.title,
            message: message,
            detail: error.message,
            quiet: quiet
        )
    }

    @MainActor static func presentGUI(error: DropletError, fileURL: URL, state: AppState) {
        state.pushMessage(
            level: error.logLevel,
            "Droplet: \(error.title) — \(fileURL.lastPathComponent)",
            filename: fileURL.lastPathComponent,
            code: error.logCode,
            originKey: "droplet-gui",
            detail: error.message
        )
    }

    private static func showCLIErrorDialog(title: String, message: String, detail: String, quiet: Bool) {
        guard !quiet else { return }

        let present = {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = "\(message)\n\n\(detail)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")

            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            app.activate(ignoringOtherApps: true)

            alert.runModal()

            app.setActivationPolicy(.accessory)
        }

        if Thread.isMainThread {
            present()
        } else {
            DispatchQueue.main.sync {
                present()
            }
        }
    }



    // MARK: - Utilities

    private static func parsePathArgument(_ arguments: [String], flag: String) -> (nextIndex: Int, path: String)? {
        for (index, arg) in arguments.enumerated() {
            if arg == flag {
                if index + 1 < arguments.count {
                    return (index + 2, arguments[index + 1])
                }
            } else if arg.hasPrefix(flag + "=") {
                let path = String(arg.dropFirst(flag.count + 1))
                return (index + 1, path)
            }
        }
        return nil
    }

    private static func findFFmpegPath() -> String {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["ffmpeg"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        if (try? whichProcess.run()) != nil {
            whichProcess.waitUntilExit()
            if whichProcess.terminationStatus == 0,
               let data = try? pipe.fileHandleForReading.readToEnd(),
               let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        }

        return "ffmpeg"
    }

    private static func extractJobID(from output: String) -> String? {
        if let match = output.range(of: #"\[([0-9a-f]{24})\]"#, options: .regularExpression) {
            return String(output[match]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        return nil
    }

    private static func parseHHMMSS(_ s: String) -> Double {
        let parts = s.split(separator: ":")
        guard parts.count == 3 else { return 0 }
        let hours = Double(parts[0]) ?? 0
        let minutes = Double(parts[1]) ?? 0
        let seconds = Double(parts[2]) ?? 0
        return (hours * 3600) + (minutes * 60) + seconds
    }

    private static func printCLIHelp() {
        print("""
MrEncode Command Line Interface

Usage:
  MrEncode --cli --droplet <preset.json> <file1.mov> [file2.mov] ...
  MrEncode --help

Options:
  --cli                 Run in CLI mode (no GUI)
  --droplet <file>      Use droplet preset file
  --quiet, -quiet       Suppress status popups (NSAlert dialogs)
  --mute, -mute         Suppress audio chime on finish
  --help, -h            Show this help message

Examples:
  # Process files with a droplet preset
  MrEncode --cli --droplet MyPreset.json video1.mov video2.mov

  # For GUI droplet mode (current behavior)
  MrEncode --droplet MyPreset.json video1.mov video2.mov
""")
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

