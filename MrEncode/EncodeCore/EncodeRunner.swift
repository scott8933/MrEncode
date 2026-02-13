//
//  EncodeRunner.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/19/25.
//


import Foundation
#if !MR_ENCODE_CLI
import AppKit
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif


/// Handles CLI droplet execution and shared droplet validation logic.
struct EncodeRunner {
    
    public typealias EncodeEventSink = (EncodeEvent) -> Void
    public typealias EncodeEventSinkWithContext = (_ index1: Int, _ total: Int, _ ev: EncodeEvent) -> Void

    static func run(arguments: [String]) -> Int {

        // Centralized flag parsing (single source of truth)
        let flags = RuntimeFlags.parse(arguments)
        let quiet = flags.quiet
        let suppressChime = flags.suppressChime

        let progressMode = parseProgressMode(arguments)
        let progressFileURL = parseProgressFileURL(arguments)
        let progressPrinter = CLIProgressPrinter(mode: progressMode, progressFileURL: progressFileURL)
        if let url = progressFileURL {
            fputs("MrEncode progress file: \(url.path)\n", stderr)
        }
        
        var exitCode: Int = 0
        defer { progressPrinter.emitBatchDone(ok: exitCode == 0) }

        // Optional runtime debug (off by default; enable via env var)
        let debugCLI = ProcessInfo.processInfo.environment["MR_ENCODE_DEBUG_CLI"] == "1"

        // Help
        if arguments.contains("--help") || arguments.contains("-h") {
            printCLIHelp()
            exitCode = 0
            return exitCode
        }

        // If the droplet gave us a log path, redirect stdout/stderr immediately.
        // Intended for explicit troubleshooting only (do not enable by default).
        if let logPath = parseStringArgument(arguments, flag: "--droplet-debug-log") {
            let logURL = URL(fileURLWithPath: logPath)
            do {
                try FileManager.default.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                // If we can't create the dir, fall back to stdout; don't abort the encode.
                if debugCLI {
                    print("[MrEncode][CLI] Could not create log directory: \(error)")
                    fflush(stdout)
                }
            }

            Self.redirectStdStreams(to: logPath)

            // Single confirmation line (useful when inspecting the log itself)
            print("MrEncode CLI logging to: \(logPath)")
            fflush(stdout)
        } else if debugCLI {
            // Debug-only: confirm progress configuration (replaces previous unconditional DEBUG spam)
            print("[MrEncode][CLI] progressMode=\(progressMode)")
            print("[MrEncode][CLI] progressFile=\(progressFileURL?.path ?? "nil")")
            if let url = progressFileURL {
                print("[MrEncode][CLI] progressFileExists=\(FileManager.default.fileExists(atPath: url.path))")
            }
            fflush(stdout)
        }
        
        // -----------------------------
        // Preset / Settings source selection (exactly one)
        // -----------------------------

        let dropletArg   = parsePathArgument(arguments, flag: "--droplet")
        let legacyArg    = parsePathArgument(arguments, flag: "--preset-file") // legacy alias for droplet
        let settingsFile = parsePathArgument(arguments, flag: "--settings-file")
        let settingsJSON = parseStringArgument(arguments, flag: "--settings-json")
        let settingsStdin = arguments.contains("--settings-stdin")

        let sourceCount =
            (dropletArg != nil ? 1 : 0) +
            (legacyArg != nil ? 1 : 0) +
            (settingsFile != nil ? 1 : 0) +
            (settingsJSON != nil ? 1 : 0) +
            (settingsStdin ? 1 : 0)

        // Back-compat: allow --preset-file OR --droplet, but not both.
        // Also disallow mixing droplet/preset-file with settings-* options.
        if sourceCount == 0 {
            print("Error: No preset/settings provided. Use --help for usage.")
            exitCode = 1
            return exitCode
        }
        if sourceCount > 1 {
            print("Error: Provide exactly one of: --droplet, --preset-file, --settings-file, --settings-json, --settings-stdin.")
            exitCode = 1
            return exitCode
        }

        // Media paths:
        // Prefer `--` sentinel if present; otherwise use existing collection logic.
        func mediaPaths(startingAt idx: Int) -> [String] {
            if let dd = arguments.firstIndex(of: "--") {
                let after = dd + 1
                return (after < arguments.count) ? Array(arguments[after...]) : []
            }
            return collectMediaPaths(from: arguments, startingAt: idx)
        }

        // -----------------------------
        // Droplet
        // -----------------------------
        if let result = parsePathArgument(arguments, flag: "--droplet") {
            let videoFilePaths = collectMediaPaths(from: arguments, startingAt: result.nextIndex)

            exitCode = runDropletCLI(
                dropletFile: result.path,
                videoFiles: videoFilePaths,
                quiet: quiet,
                suppressChime: suppressChime,
                progressPrinter: progressPrinter
            )

            return exitCode
        }

        // -----------------------------
        // Settings JSON (new flow)
        // -----------------------------

        let loadedSettings: Settings
        do {
            if let sf = settingsFile {
                let data = try Data(contentsOf: URL(fileURLWithPath: sf.path))
                loadedSettings = try JSONDecoder().decode(Settings.self, from: data)
            } else if let json = settingsJSON {
                let data = Data(json.utf8)
                loadedSettings = try JSONDecoder().decode(Settings.self, from: data)
            } else if settingsStdin {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                loadedSettings = try JSONDecoder().decode(Settings.self, from: data)
            } else {
                print("Error: No valid preset/settings source found. Use --help for usage.")
                exitCode = 1
                return exitCode
            }
        } catch {
            print("""
            Error: Failed to load settings JSON.

            The JSON must contain all required keys to form a complete preset.
            See documentation for the minimum required fields.

            Decoder error:
            \(error)
            """)
            exitCode = 1
            return exitCode
        }

        // Determine where media args start for non-stdin modes
        let startIndex: Int = {
            if let r = settingsFile { return r.nextIndex }
            if arguments.contains("--settings-json"),
               let i = arguments.firstIndex(of: "--settings-json") { return i + 2 }
            if settingsStdin { return arguments.count } // force `--` sentinel usage
            exitCode = 0
            return exitCode
        }()

        let videoFilePaths = mediaPaths(startingAt: startIndex)

        return runSettingsCLI(
            settings: loadedSettings,
            videoFiles: videoFilePaths,
            quiet: quiet,
            suppressChime: suppressChime,
            progressPrinter: progressPrinter
        )
    }



    // MARK: - Droplet CLI
    
#if !MR_ENCODE_CLI
    private static func fireDoneChimeIfAllowed(suppressChime: Bool) {
        guard !suppressChime else { return }
        Task { @MainActor in
            SoundManager.shared.playDoneChime()
        }
    }
    #else
    private static func fireDoneChimeIfAllowed(suppressChime: Bool) {
        guard !suppressChime else { return }
        FileHandle.standardError.write(Data("\u{07}".utf8)) // BEL
    }
#endif



    /// Gives the main runloop a brief chance to execute scheduled @MainActor work.
    /// Use this only for the "quiet + chime-only" case.
    private static func pumpMainRunLoop(seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        RunLoop.main.run(until: until)
    }


    private static func runDropletCLI(
        dropletFile: String,
        videoFiles: [String],
        quiet: Bool,
        suppressChime: Bool,
        progressPrinter: CLIProgressPrinter
    ) -> Int
    {
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

        return runWithSettings(
            settings: droplet.settings,
            presetNameForDialogs: droplet.presetName,
            dropletFileURL: URL(fileURLWithPath: dropletFile),
            inputURLs: videoFiles.map { URL(fileURLWithPath: $0) },
            quiet: quiet,
            suppressChime: suppressChime,
            progressPrinter: progressPrinter
        )
    }

    /// Processes a single media file with the provided settings.
    /// Returns a `Result` so CLI and GUI wrappers can report failures differently and unit tests
    /// can cover each error scenario without depending on alerts.
    static func processFile(
        fileURL: URL,
        settings: Settings,
        dropletFileURL: URL,
        emit: @escaping EncodeEventSink,
        jobIDSink: ((String) -> Void)? = nil
    ) -> Result<Void, DropletError> {

        // Probe metadata (your existing path)
        let meta = MetadataExtractor.extract(for: fileURL)
        let item = MediaItem(url: fileURL, meta: meta, status: .queued)

        // Output naming (your existing path)
        let outputURL = OutputNamer.suggestedOutputURL(for: fileURL, settings: settings)

        // Validate (your existing path)
        switch validateFileForProcessing(item: item, settings: settings) {
        case .success:
            break
        case .failure(let error):
            emit(.failed(.init(.invalidInput, error.message))) // best-effort signal for CLI/Deadline
            return .failure(error)
        }

        // Helpful per-file header
        emit(.phase(.preparing))
        emit(.warning("Input: \(fileURL.lastPathComponent)"))

        switch settings.runMode {

        case .localNative:
            emit(.phase(.preparing))
            emit(.warning("Encoding (local): \(fileURL.lastPathComponent)"))

            // Optional: warn once that this is native VT now (keeps logs accurate while enum is stale)
            emit(.warning("MODE: Local (native AVFoundation/VideoToolbox)"))

            // Cancellation: if you later add SIGINT/global cancel in CLI, plug it in here.
            let cancel: CancelCheck = { false }

            // No overlays in CLI currently. If you ever want CLI burn-ins, we can add a hook here.
            let request = EncodeRequest(
                inputURL: fileURL,
                outputURL: outputURL,
                allowOverwrite: true, // If droplets have an overwrite flag, pass it through here.
                settings: settings,
                meta: meta,
                filenameForOverlay: fileURL.lastPathComponent,
                videoFrameHook: nil
            )

            let engineResult = EncodeEngine.encode(
                request,
                cancel: cancel,
                emit: emit
            )

            switch engineResult {
            case .success:
                return .success(())

            case .failure(let e):
                if e.code == .cancelled {
                    return .failure(.cancelled(message: e.message))
                } else {
                    return .failure(.encodeFailed(message: e.message))
                }
            }


        case .remoteDeadline:
            emit(.phase(.preparing))
            emit(.warning("Submitting (Deadline): \(fileURL.lastPathComponent)"))

            return runRemoteEncodeCLI(
                item: item,
                output: outputURL,
                settings: settings,
                dropletFileURL: dropletFileURL,
                jobIDSink: jobIDSink
            )
        }
    }


    /// Convenience batch helper used by CLI/GUI wrappers and unit tests.
    static func processFiles(
        _ fileURLs: [URL],
        settings: Settings,
        dropletFileURL: URL,
        emit: @escaping EncodeEventSinkWithContext,
        jobIDSink: ((URL, String) -> Void)? = nil
    ) -> [(url: URL, result: Result<Void, DropletError>)] {

        let total = fileURLs.count

        return fileURLs.enumerated().map { (i0, url) in
            let index1 = i0 + 1

            // Per-file boundary event (now with context)
            emit(index1, total, .warning("Processing: \(url.lastPathComponent)"))

            let result = processFile(
                fileURL: url,
                settings: settings,
                dropletFileURL: dropletFileURL,

                // Adapt the old per-file emitter to the contextual emitter
                emit: { ev in
                    emit(index1, total, ev)
                },

                jobIDSink: { jobID in jobIDSink?(url, jobID) }
            )

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

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.validation(message: "File does not exist or is not accessible."))
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return .failure(.validation(message: "File exists but cannot be read. Check file permissions."))
        }

        // Capability-based probe, same as main app - no extension gating
        let probe = MediaProbeService.probeVideoDecode(url)
        if !probe.hasVideo {
            return .failure(.validation(message: "No video track found in \(url.lastPathComponent)"))
        }
        if !probe.canDecode {
            return .failure(.validation(message: "AVFoundation cannot decode \(url.lastPathComponent). The codec may not be supported on this system."))
        }

        if settings.runMode == .remoteDeadline {
            if case .failure(let error) = EncodeRenderfarm.isInputPathAcceptableForFarm(url) {
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
    
    
    // MARK: - CLI Helpers
    
#if !MR_ENCODE_CLI
    private static func ensureAppKitInitialized() {
        _ = NSApplication.shared
    }
    #else
    private static func ensureAppKitInitialized() {
        // CLI build: never touch AppKit
    }
#endif

    
    private func redirectStdStreams(to path: String) {
        // Best-effort; never crash CLI because logging failed.
        // Use append mode so multiple runs accumulate.
        let cPath = (path as NSString).fileSystemRepresentation

        guard let f = fopen(cPath, "a") else { return }

        // Route stdout/stderr to the file.
        dup2(fileno(f), fileno(stdout))
        dup2(fileno(f), fileno(stderr))

        // Line-buffered output helps keep logs usable without forcing fsync.
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)

        // We intentionally do not fclose(f) here.
        // Closing could invalidate stdout/stderr since they now share the fd.
    }
    
    private static func parseStringFlag(_ args: [String], flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func parseProgressMode(_ args: [String]) -> CLIProgressPrinter.Mode {
        if let s = parseStringFlag(args, flag: "--progress")?.lowercased() {
            switch s {
            case "human": return .human
            case "json":  return .json
            case "none":  return .none
            default: break
            }
        }
        // Default: human when attached to a terminal; json otherwise (droplet/farm safer)
        return isatty(fileno(stdout)) != 0 ? .human : .json
    }

    private static func parseProgressFileURL(_ args: [String]) -> URL? {
        guard let s = parseStringFlag(args, flag: "--progress-file") else { return nil }
        return URL(fileURLWithPath: s)
    }
    
    private static func collectMediaArgs(_ arguments: [String], startIndex: Int) -> [String] {
        // If a "--" sentinel exists, treat everything after it as media paths.
        if let dd = arguments.firstIndex(of: "--") {
            let after = arguments.index(after: dd)
            if after < arguments.endIndex {
                return Array(arguments[after...])
            }
            return []
        }

        // Otherwise: use existing behavior from startIndex onward,
        // but skip known flags and their values.
        var out: [String] = []
        var i = startIndex

        while i < arguments.count {
            let a = arguments[i]

            if RuntimeFlags.flagsWithValue.contains(a) {
                i += 2
                continue
            }
            if RuntimeFlags.booleanFlags.contains(a) {
                i += 1
                continue
            }

            out.append(a)
            i += 1
        }

        return out
    }

    private static func parseStringArgument(_ args: [String], flag: String) -> String? {
        guard let i = args.firstIndex(of: flag) else { return nil }
        let v = i + 1
        guard v < args.count else { return nil }
        return args[v]
    }

    private static func runSettingsCLI(
        settings: Settings,
        videoFiles: [String],
        quiet: Bool,
        suppressChime: Bool,
        progressPrinter: CLIProgressPrinter
    ) -> Int {

        // Validate media arguments early (match droplet behavior)
        if videoFiles.isEmpty {
            if !quiet { fputs("Error: no input files provided.\n", stderr) }
            return 2
        }

        // Materialize a real DropletFile (because remoteDeadline needs dropletFileURL)
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
            .appendingPathComponent("MrEncode", isDirectory: true)
            .appendingPathComponent("CLI", isDirectory: true)

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        } catch {
            if !quiet { fputs("Error: failed to create temp directory: \(error)\n", stderr) }
            return 1
        }

        let dropletURL = tmpDir.appendingPathComponent("mrencode-\(UUID().uuidString).mrdroplet")

        do {
            let droplet = DropletFile(presetName: "CLI Settings", settings: settings)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(droplet)
            try data.write(to: dropletURL, options: [.atomic])
        } catch {
            if !quiet { fputs("Error: failed to write temp droplet: \(error)\n", stderr) }
            return 1
        }

        defer { try? fm.removeItem(at: dropletURL) }

        // Reuse the exact same droplet pipeline
        return runDropletCLI(
            dropletFile: dropletURL.path,
            videoFiles: videoFiles,
            quiet: quiet,
            suppressChime: suppressChime,
            progressPrinter: progressPrinter
        )
    }

    
    // MARK: - Execution Helpers

    static func runLocalEncodeCLI(
        item: MediaItem,
        output: URL,
        settings: Settings,
        emit: @escaping EncodeEventSink
    ) -> Result<Void, DropletError> {

        let request = EncodeRequest(
            inputURL: item.url,
            outputURL: output,
            allowOverwrite: true,
            settings: settings,
            meta: item.meta,
            filenameForOverlay: item.url.lastPathComponent,
            videoFrameHook: nil
        )

        let r = EncodeEngine.encode(request, cancel: { false }, emit: emit)

        switch r {
        case .success:
            return .success(())
        case .failure(let e):
            if e.code == .cancelled { return .failure(.cancelled(message: e.message)) }
            return .failure(.encodeFailed(message: e.message))
        }
    }


    /// The `dropletFileURL` is the original preset file from the command line (e.g. .mrepreset).
        /// It already contains the serialised Settings and is already on whatever
        /// path the user invoked — no need to write or copy a temp preset.
        private static func runRemoteEncodeCLI(item: MediaItem,
                                               output: URL,
                                               settings: Settings,
                                               dropletFileURL: URL,
                                               jobIDSink: ((String) -> Void)? = nil) -> Result<Void, DropletError> {
            let deadlineCmd = settings.deadlineCommandPath.isEmpty
                ? (EncodeRenderfarm.detectDeadlineCommand() ?? "/Applications/Thinkbox/Deadline10/Resources/deadlinecommand")
                : settings.deadlineCommandPath

            guard FileManager.default.isExecutableFile(atPath: deadlineCmd) else {
                return .failure(.deadlineFailed(
                    message: "Deadline command not found at: \(deadlineCmd)\n\n"
                           + "This droplet was created for Deadline rendering, but Deadline "
                           + "is not installed or not accessible on this machine."))
            }

            print("  Submitting to Deadline…")

            let result = EncodeRenderfarm.submitShellJob(
                deadlineCmd: deadlineCmd,
                presetURL:   dropletFileURL,
                input:       item.url,
                output:      output,
                settings:    settings)

            if result.exitCode == 0 {
                if let jid = result.jobID, !jid.isEmpty {
                    jobIDSink?(jid)
                }
                return .success(())
            } else {
                let detail = "Deadline submission failed with exit code \(result.exitCode).\n\n"
                           + "Deadline output:\n\(result.rawOutput.prefix(500))"
                return .failure(.deadlineFailed(message: detail))
            }
        }
    
    
    private static func writeTempDropletFile(
        presetName: String,
        settings: Settings
    ) throws -> URL {

        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("MrEncode", isDirectory: true)
            .appendingPathComponent("CLI", isDirectory: true)

        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

        // Use a droplet-ish extension for readability. It’s still JSON inside.
        let url = dir.appendingPathComponent("mrencode-\(UUID().uuidString).mrdroplet")

        let droplet = DropletFile(presetName: presetName, settings: settings)

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try enc.encode(droplet)
        try data.write(to: url, options: [.atomic])

        return url
    }
    
    
    private static func runWithSettings(
        settings: Settings,
        presetNameForDialogs: String,
        dropletFileURL: URL,
        inputURLs: [URL],
        quiet: Bool,
        suppressChime: Bool,
        progressPrinter: CLIProgressPrinter
    ) -> Int {

        // NOTE: This function is intentionally "pure CLI":
        // - no NSAlert
        // - no showCLIErrorDialog
        // - no AppKit init / activation policy changes
        // Droplet-mode alerts/confirmations should be handled by AppleScript before invoking CLI.

        // Helper: only do interactive behaviors (like stdin prompts / terminal bell) if we have a real TTY.
        // This prevents droplet/background runs from hanging on stdin reads.
        let isInteractiveTTY: Bool = {
            // Prevent droplet/background runs from blocking on stdin.
            return isatty(STDIN_FILENO) != 0 && isatty(STDERR_FILENO) != 0
        }()


        // Convert paths to URLs and process through QueueImportService (handles folders, filtering, etc.)
        let importResult = QueueImportService.process(inputURLs)

        // Print warnings (folder scan messages) — NO dialogs.
        if !importResult.warnings.isEmpty {
            let warningMessage = importResult.warnings.joined(separator: "\n\n")
            if !quiet {
                print("Warnings during import:")
                print(warningMessage)
            }
        }

        // Print rejected files message (non-modal, just print to console)
        if !importResult.rejectedFilenames.isEmpty && !quiet {
            let list = importResult.rejectedFilenames.count > 5
                ? importResult.rejectedFilenames.prefix(5).joined(separator: ", ")
                    + ", and \(importResult.rejectedFilenames.count - 5) more"
                : importResult.rejectedFilenames.joined(separator: ", ")

            print("Skipped unsupported media: \(list)")
        }

        // Confirmation (>25 files):
        // - Droplet mode should confirm in AppleScript, not here.
        // - Pure CLI can still prompt IF interactive; otherwise proceed without blocking.
        if importResult.requiresConfirm && !quiet {
            let count = importResult.candidates.count

            if isInteractiveTTY {
                let prompt = "About to process \(count) media file(s). Continue? [y/N]: "
                FileHandle.standardError.write(Data(prompt.utf8))

                let data = FileHandle.standardInput.availableData
                let line = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() ?? ""

                if !(line == "y" || line == "yes") {
                    fputs("Cancelled.\n", stderr)
                    return 0
                }
            } else {
                // Non-interactive (droplet/background): never block on stdin.
                print("Note: processing \(count) media file(s) (non-interactive; skipping confirmation prompt).")
            }
        }

        guard !importResult.candidates.isEmpty else {
            // NO dialogs — just print and exit nonzero.
            let fileList = inputURLs.map { $0.lastPathComponent }.joined(separator: ", ")
            print("Error: No supported video files found")
            if !quiet {
                print("Files/folders provided: \(fileList.isEmpty ? "None" : fileList)")
            }
            return 1
        }

        if !quiet {
            print("Processing \(importResult.candidates.count) video file(s)...")
        }

        var successCount = 0
        var failureCount = 0
        var errors: [(file: String, error: DropletError)] = []
        var submittedJobIDs: [String] = []
        var cancelCount = 0

        progressPrinter.sink(.phase(.preparing))

        let results = processFiles(
            importResult.candidates,
            settings: settings,
            dropletFileURL: dropletFileURL,
            emit: { index1, total, ev in
                switch ev {
                case .progress(let pr):
                    var out = pr

                    // Simple status line the helper will display
                    out.message = "Encoding \(index1) of \(total)"

                    // Map per-file fraction (0...1) to overall batch fraction (0...1)
                    let f = max(0.0, min(1.0, pr.fraction))
                    out.fraction = (Double(index1 - 1) + f) / Double(max(total, 1))

                    progressPrinter.sink(.progress(out))

                default:
                    progressPrinter.sink(ev)
                }
            }
        ) { _, jobID in
            guard !jobID.isEmpty else { return }
            submittedJobIDs.append(jobID)
            if !quiet { print("  Submitted as job: \(jobID)") }
        }

        for (index, entry) in results.enumerated() {
            let fileURL = entry.url
            if !quiet {
                print("[\(index + 1)/\(results.count)] Processing: \(fileURL.lastPathComponent)")
            }

            switch entry.result {
            case .success:
                successCount += 1
                if !quiet { print("  ✓ Complete") }

            case .failure(let error):
                if case .cancelled = error {
                    cancelCount += 1
                    if !quiet { print("  — Cancelled") }
                } else {
                    failureCount += 1
                    errors.append((file: fileURL.lastPathComponent, error: error))
                    // Always print failures even in quiet mode (otherwise it’s opaque).
                    print("  ✗ Failed: \(error.message)")
                }
            }
        }

        // Summary
        if !quiet {
            print("\nProcessing complete.")
            print("Successful: \(successCount)")
            print("Failed: \(failureCount)")
            if cancelCount > 0 { print("Cancelled: \(cancelCount)") }
        } else {
            // In quiet mode, still print *something* if there were failures.
            if failureCount > 0 {
                print("Processing complete with failures. Successful: \(successCount) Failed: \(failureCount)")
            }
        }

        if failureCount > 0 {
            if !quiet {
                let failedList = errors
                    .map { "• \($0.file): \($0.error.message)" }
                    .joined(separator: "\n")

                print("\nFailed files:\n\(failedList)")
            }
            
            progressPrinter.sink(.progress(EncodeProgress(
                fraction: 1.0,
                message: "Failed — encoded \(successCount) item(s), \(failureCount) failed"
            )))
            
            return 1
        }

        // Optional: terminal bell for interactive shells only (never triggers GUI)
        if !suppressChime && isInteractiveTTY && !quiet {
            FileHandle.standardError.write(Data("\u{07}".utf8)) // BEL
        }
        
        progressPrinter.sink(.progress(EncodeProgress(
            fraction: 1.0,
            message: "Done — encoded \(successCount) item(s)"
        )))

        return 0
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
    

#if !MR_ENCODE_CLI
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
#endif

    
#if !MR_ENCODE_CLI
    private static func showCLIErrorDialog(
        title: String,
        message: String,
        detail: String,
        quiet: Bool
    ) {
        guard !quiet else { return }

        let present = {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = "\(message)\n\n\(detail)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")

            let app = NSApplication.shared
            app.setActivationPolicy(.regular)

            // Force the app to front
            NSRunningApplication.current.activate(
                options: [.activateAllWindows, .activateIgnoringOtherApps]
            )

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
#else
    private static func showCLIErrorDialog(
        title: String,
        message: String,
        detail: String,
        quiet: Bool
    ) {
        guard !quiet else { return }

        // CLI-safe error reporting
        fputs("\n\(title)\n", stderr)
        fputs("\(message)\n", stderr)
        if !detail.isEmpty {
            fputs("\(detail)\n", stderr)
        }
    }
#endif


    // MARK: - Mappers
    
    private struct BatchProgressContext {
        let index1: Int     // 1-based
        let total: Int
    }

    /// Maps per-item progress (0-1) to overall batch progress (0-1)
    private func overallFraction(itemFraction: Double, ctx: BatchProgressContext) -> Double {
        guard ctx.total > 0 else { return itemFraction }
        let clamped = max(0.0, min(1.0, itemFraction))
        return (Double(ctx.index1 - 1) + clamped) / Double(ctx.total)
    }
    

    private func mapEventForBatchUI(_ ev: EncodeEvent, ctx: BatchProgressContext) -> EncodeEvent {
        switch ev {
        case .progress(var pr):
            pr.message = "Encoding \(ctx.index1) of \(ctx.total)"
            pr.fraction = overallFraction(itemFraction: pr.fraction, ctx: ctx)
            return .progress(pr)

        default:
            return ev
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

    private static func extractJobID(from output: String) -> String? {
        if let match = output.range(of: #"\[([0-9a-f]{24})\]"#, options: .regularExpression) {
            return String(output[match]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        return nil
    }
    
    
    private static func redirectStdStreams(to path: String) {
        // Best-effort; never crash CLI because logging failed.
        // Use append mode so multiple runs accumulate.
        let cPath = (path as NSString).fileSystemRepresentation

        guard let f = fopen(cPath, "a") else { return }

        dup2(fileno(f), fileno(stdout))
        dup2(fileno(f), fileno(stderr))
        setvbuf(stdout, nil, _IOLBF, 0) // line-buffered
        setvbuf(stderr, nil, _IOLBF, 0)

        // Intentionally do not fclose(f) here.
    }

    
    
    // MARK: - CLI Help

    private static func printCLIHelp() {
        print("""
MrEncode Command Line Interface

Usage:
  mrencode --help
  mrencode --preset <Preset.mrepreset> <media1> [media2 ...]
  mrencode --droplet <Preset.mrepreset|Preset.json> <media1> [media2 ...]
  mrencode --run-mode local|remote-deadline --preset <Preset.mrepreset> <media...>

Options:
  --preset <file>           Preset snapshot (.mrepreset). Full, immutable settings.
  --droplet <file>          Preset file used by droplets. Supports .mrepreset (preferred) and legacy .json.
  --run-mode <mode>         local (default) or remote-deadline (submit to farm).
  --quiet, -quiet           Reduce console output / suppress interactive prompts.
  --mute, -mute             Suppress completion chime (GUI). CLI uses terminal bell only.
  --help, -h                Show this help message

Examples:
  # Encode locally using a preset snapshot
  mrencode --preset GoodQuality_Local.mrepreset input.mov

  # Encode multiple inputs with the same preset
  mrencode --preset GoodQuality_Local.mrepreset a.mov b.mp4

  # Submit to Deadline (inputs must be on shared storage)
  mrencode --run-mode remote-deadline --preset FarmPreset.mrepreset /Volumes/Share/foo.mov

Notes:
  • Presets are full snapshots (.mrepreset). There is no merging of settings.
  • In remote-deadline mode, inputs must be on shared/network storage (e.g. /Volumes/Share/...),
    not local paths like Desktop or Downloads.

Supported Formats:
  Any media format decodable by macOS AVFoundation / VideoToolbox.
  (Typical: .mov, .mp4, .m4v; codec support varies by macOS version.)

Encoding Backend:
  Local: native VideoToolbox-based encoding (no external encoder dependency).
  Remote-deadline: submits a job to Deadline using deadlinecommand (encode occurs on the farm).

""")
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
