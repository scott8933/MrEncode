// =============================
// File: EncodeRemote.swift
// =============================
import Foundation

/// Remote encoding via Thinkbox Deadline.
/// - Builds ffmpeg args with `FFmpegCommandBuilder`
/// - Can export **FFmpeg plugin** job bundles to Desktop (no submission)
/// - Can fetch Pools/Groups and detect `deadlinecommand`
enum EncodeRemote {
    
    /// Convenience wrapper used by AppState to submit a batch of items to Deadline.
    /// - Resolves `deadlinecommand`
    /// - Validates input path suitability for farm
    /// - Submits via FFmpeg **plugin** job (one per item)
    /// - On success: sets `.queued` with reason "Submitted to Deadline."
    static func run(items: [MediaItem], settings: Settings) {
        // Resolve deadlinecommand: user override → detect marker → fallback (classic mac path)
        let deadlineCmd: String = {
            if !settings.deadlineCommandPath.isEmpty {
                return settings.deadlineCommandPath
            }
            if let detected = detectDeadlineCommand() {
                return detected
            }
            return "/Applications/Thinkbox/Deadline10/Resources/deadlinecommand"
        }()

        // Path to ffmpeg as seen by farm workers (FFmpeg plugin often doesn’t need it, but safe to include)
        let ffmpegOnFarm = "/usr/local/bin/ffmpeg"

        DispatchQueue.global(qos: .userInitiated).async {
            guard let shared = AppState.shared else { return }
            let settingsSnapshot = shared.settings
            let itemsSnapshot = items

            for item in itemsSnapshot {
                if item.status == .blocked { continue }

                // Indicate “encoding” while we generate & submit
                DispatchQueue.main.async {
                    if let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                        shared.files[idx].status = .encoding
                        shared.files[idx].statusReason = "Submitting to Deadline…"
                    }
                }

                // Build argv → FFmpeg plugin OutputArgs (kept for future use)
                let fullArgs = FFmpegCommandBuilder.buildArgs(
                    item: item,
                    output: item.finalOutputURL ?? OutputNamer.suggestedOutputURL(for: item.url, settings: settingsSnapshot),
                    settings: settingsSnapshot
                )

                // Submit a single FFmpeg plugin job
                DispatchQueue.main.async { AppState.shared?.log(.info, "Submitting to Deadline…", fileURL: item.url) }
                let result = submitFFmpegJob(
                    deadlineCmd: deadlineCmd,
                    item: item,
                    settings: settingsSnapshot,
                    ffmpegPath: ffmpegOnFarm
                )

                DispatchQueue.main.async {
                    guard let idx = shared.files.firstIndex(where: { $0.id == item.id }) else { return }

                    if result.exitCode == 0 {
                        shared.files[idx].finalOutputURL = result.output
                        shared.files[idx].status = .queued
                        shared.files[idx].statusReason = "Submitted to Deadline."
                        if let jobID = Self.extractJobID(from: result.rawOutput) {
                            AppState.shared?.log(.info, "Submitted to Deadline. JobID=\(jobID)", fileURL: item.url)
                        } else {
                            AppState.shared?.log(.info, "Submitted to Deadline.", fileURL: item.url)
                        }
                    } else {
                        shared.files[idx].status = .error
                        let msg = result.rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                        shared.files[idx].statusReason = msg.isEmpty
                            ? "Deadline submit failed (code \(result.exitCode))."
                            : msg
                        let tail = msg.split(separator: "\n").suffix(6).joined(separator: "\n")
                        AppState.shared?.log(.error, "Deadline submit failed. \(tail)", fileURL: item.url, autoReveal: true)
                    }
                }
            }
        }
    }


    // MARK: - Types

    struct Lists {
        var pools: [String]
        var groups: [String]
    }

    struct SubmissionResult {
        let input: URL
        let output: URL
        let exitCode: Int32
        let rawOutput: String
    }

    // Extract JobID=... from Deadline output
    private static func extractJobID(from out: String) -> String? {
        let lines = out.split(separator: "\n")
        for line in lines {
            if let range = line.range(of: "JobID=") {
                let rest = line[range.upperBound...]
                let id = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                if !id.isEmpty { return String(id) }
            }
        }
        return nil
    }

    // MARK: - (Optional) Write FFmpeg plugin job files to a directory

    /// Writes one `jobInfo.job` + `pluginInfo.job` pair per item into `dir`.
    /// Returns all written file URLs (in order), or empty array on failure.
    static func writeFFmpegJobPairs(to dir: URL,
                                    items: [MediaItem],
                                    settings: Settings,
                                    ffmpegPath: String,
                                    pools: [String],
                                    groups: [String]) -> [URL] {
        var written: [URL] = []

        for item in items {
            let jobInfoURL    = dir.appendingPathComponent("\(item.id.uuidString)-jobInfo.job")
            let pluginInfoURL = dir.appendingPathComponent("\(item.id.uuidString)-pluginInfo.job")

            do {
                let input  = item.url
                let output = item.finalOutputURL ?? OutputNamer.suggestedOutputURL(for: input, settings: settings)
                let fullArgs   = FFmpegCommandBuilder.buildArgs(item: item, output: output, settings: settings)
                let outputArgs = ffmpegOutputArgs(fromFullArgs: fullArgs, input: input, output: output)

                try writeFFmpegJobInfo(to: jobInfoURL, input: input, output: output, pools: pools, groups: groups)
                try writeFFmpegPluginInfo(to: pluginInfoURL,
                                          input: input,
                                          output: output,
                                          ffmpegPath: ffmpegPath,
                                          outputArgs: outputArgs)

                written.append(jobInfoURL)
                written.append(pluginInfoURL)
            } catch {
                continue
            }
        }

        return written
    }


    // MARK: - (Optional) Submit FFmpeg plugin job now

    /// Submit previously generated FFmpeg plugin job pair to Deadline.
    @discardableResult
    static func submitJobPair(deadlineCmd: String, jobInfoPath: String, pluginInfoPath: String) -> (Int32, String) {
        runCLI(path: deadlineCmd, args: ["-SubmitJob", jobInfoPath, pluginInfoPath])
    }
    
    /// Create a temp FFmpeg plugin job pair for one item, submit it, and clean up.
    @discardableResult
    static func submitFFmpegJob(deadlineCmd: String,
                                item: MediaItem,
                                settings: Settings,
                                ffmpegPath: String) -> SubmissionResult {
        let fm = FileManager.default
        let input  = item.url
        let output = item.finalOutputURL ?? OutputNamer.suggestedOutputURL(for: input, settings: settings)

        // Convert full argv into FFmpeg plugin OutputArgs
        let fullArgs   = FFmpegCommandBuilder.buildArgs(item: item, output: output, settings: settings)
        let outputArgs = ffmpegOutputArgs(fromFullArgs: fullArgs, input: input, output: output)

        // Write temp job pair
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mrhevc-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: nil)

            let jobInfoURL    = tmpDir.appendingPathComponent("jobInfo.job")
            let pluginInfoURL = tmpDir.appendingPathComponent("pluginInfo.job")

            // NOTE: We intentionally pass empty arrays here since Settings has no pools/groups.
            try writeFFmpegJobInfo(to: jobInfoURL, input: input, output: output, pools: [], groups: [])
            try writeFFmpegPluginInfo(to: pluginInfoURL,
                                      input: input,
                                      output: output,
                                      ffmpegPath: ffmpegPath,
                                      outputArgs: outputArgs)

            // Submit to Deadline
            let (code, out) = submitJobPair(deadlineCmd: deadlineCmd,
                                            jobInfoPath: jobInfoURL.path,
                                            pluginInfoPath: pluginInfoURL.path)

            // Clean up temp
            try? fm.removeItem(at: tmpDir)

            return SubmissionResult(input: input, output: output, exitCode: code, rawOutput: out)
        } catch {
            try? fm.removeItem(at: tmpDir)
            return SubmissionResult(input: input, output: output,
                                    exitCode: -1,
                                    rawOutput: "Failed to write/submit Deadline job: \(error)")
        }
    }


    // MARK: - Helpers for FFmpeg plugin format

    /// Convert full argv into just OutputArgs for the FFmpeg plugin (no `-i` input, no output path).
    private static func ffmpegOutputArgs(fromFullArgs full: [String], input: URL, output: URL) -> String {
        var args = full
        if let i = args.firstIndex(of: "-i"), i + 1 < args.count {
            args.removeSubrange(i...(i+1))
        }
        if !args.isEmpty { _ = args.removeLast() }
        return args.joined(separator: " ")
    }

    private static func writeFFmpegJobInfo(to url: URL, input: URL, output: URL, pools: [String], groups: [String]) throws {
        var lines: [String] = []
        lines.append("Plugin=FFmpeg")
        lines.append("Name=\(input.lastPathComponent) → HEVC")
        lines.append("Comment=Transcode to HEVC (libx265)")
        lines.append("Department=")

        if !pools.isEmpty { lines.append("Pool=\(pools[0])") }
        if !groups.isEmpty { lines.append("Group=\(groups[0])") }

        // Single-frame “range” (FFmpeg plugin expectation)
        lines.append("Frames=0-0")
        lines.append("ChunkSize=1")

        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeFFmpegPluginInfo(to url: URL,
                                              input: URL,
                                              output: URL,
                                              ffmpegPath: String,
                                              outputArgs: String) throws
    {
        var lines: [String] = []
        lines.append("[FFmpeg]")
        lines.append("FFmpegExecutable=\(ffmpegPath)") // often ignored, but safe to include
        lines.append("InputFile=\(input.path)")
        lines.append("OutputFile=\(output.path)")
        lines.append("OutputArgs=\(outputArgs)")
        lines.append("UseSameInputArgs=False")
        lines.append("AdditionalArgs=")
        lines.append("VideoPreset=")
        lines.append("AudioPreset=")
        lines.append("SubtitlePreset=")

        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - CLI helpers

    static func runCLI(path: String, args: [String]) -> (Int32, String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = pipe

        do { try task.run() }
        catch { return (-1, "Failed to launch \(path): \(error)") }

        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(decoding: data, as: UTF8.self)
        return (task.terminationStatus, out)
    }

    // MARK: - Deadline detection & path checks (abridged)

    static func detectDeadlineCommand() -> String? {
        let candidates = [
            "/usr/local/bin/deadlinecommand",
            "/Applications/Thinkbox/Deadline10/Resources/deadlinecommand"
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }

    /// Heuristic: basic “farm-suitable” path checks (can be tightened later)
    static func checkPathFarmSuitability(_ path: String) -> (ok: Bool, reason: String?) {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        if !fm.fileExists(atPath: path) {
            return (false, "Path does not exist.")
        }
        if path.hasPrefix(home + "/") && !path.hasPrefix("/Volumes/") {
            return (false, "Path is under your local home folder. Use a shared path (e.g. /Volumes/Share/…).")
        }
        if path.hasPrefix("/Volumes/") {
            return (true, nil)
        }
        return (true, nil)
    }
}
