// =============================
// File: EncodeRemote.swift
// =============================
import Foundation

/// Remote encoding via Thinkbox Deadline.
/// - Builds ffmpeg args with `FFmpegCommandBuilder`
/// - Can export **FFmpeg plugin** job bundles to Desktop (no submission)
/// - Can fetch Pools/Groups and detect `deadlinecommand`
enum EncodeRemote {
    
    // MARK: - Public entry point
    
    /// Submit a batch of items to Deadline (FFmpeg plugin jobs, one per item).
    static func run(items: [MediaItem], settings: Settings) {
        let deadlineCmd = settings.deadlineCommandPath.isEmpty
            ? (detectDeadlineCommand()
               ?? "/Applications/Thinkbox/Deadline10/Resources/deadlinecommand")
            : settings.deadlineCommandPath
        
        let ffmpegOnFarm = "/usr/local/bin/ffmpeg"

        DispatchQueue.global(qos: .userInitiated).async {
            // Skip both .encoding and .blocked up front
            for item in items where item.status != .encoding && item.status != .blocked {

                // Path suitability
                let okFarm = isInputPathAcceptableForFarm(item.url)
                if !okFarm.ok {
                    DispatchQueue.main.async {
                        if let shared = AppState.shared,
                           let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                            shared.files[idx].status = .blocked
                            shared.files[idx].statusReason = okFarm.reason
                        }
                        AppState.shared?.pushMessage(
                            level: .warning,
                            okFarm.reason ?? "Path not suitable for farm access",
                            filename: item.url.lastPathComponent
                        )
                    }
                    continue
                }

                // Guard again on main right before marking as submitting
                var isBlockedNow = false
                DispatchQueue.main.sync {
                    if let shared = AppState.shared,
                       let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                        isBlockedNow = (shared.files[idx].status == .blocked)
                        if !isBlockedNow {
                            shared.files[idx].status = .queued
                            shared.files[idx].statusReason = "Submitting to Deadline…"
                        }
                    }
                }
                if isBlockedNow { continue } // don’t proceed if it flipped to blocked

                // One more quick guard before actually submitting (race-safe)
                DispatchQueue.main.sync {
                    if let shared = AppState.shared,
                       let idx = shared.files.firstIndex(where: { $0.id == item.id }),
                       shared.files[idx].status == .blocked {
                        isBlockedNow = true
                    }
                }
                if isBlockedNow { continue }

                // Submit
                let result = submitFFmpegJob(deadlineCmd: deadlineCmd,
                                             item: item,
                                             settings: settings,
                                             ffmpegPath: ffmpegOnFarm)

                // Reflect outcome
                DispatchQueue.main.async {
                    guard let shared = AppState.shared,
                          let idx = shared.files.firstIndex(where: { $0.id == item.id }) else { return }

                    if result.exitCode == 0 {
                        shared.files[idx].finalOutputURL = result.output
                        shared.files[idx].status = .queued
                        shared.files[idx].statusReason = "Submitted to Deadline."

                        if let jid = extractDeadlineJobID(from: result.rawOutput), !jid.isEmpty {
                            AppState.shared?.pushMessage(
                                level: .info,
                                "Remote submit successful — Job \(jid)",
                                filename: item.url.lastPathComponent
                            )
                        } else {
                            AppState.shared?.pushMessage(
                                level: .info,
                                "Remote submit successful",
                                filename: item.url.lastPathComponent
                            )
                        }
                    } else {
                        shared.files[idx].status = .error
                        let msg = result.rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                        shared.files[idx].statusReason = msg.isEmpty
                            ? "Deadline submit failed (code \(result.exitCode))."
                            : msg

                        AppState.shared?.pushMessage(
                            level: .error,
                            "Remote submit failed — check status",
                            filename: item.url.lastPathComponent
                        )
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

    // MARK: - Detect deadlinecommand

    static func detectDeadlineCommand() -> String? {
        let marker = "/Users/Shared/Thinkbox/DEADLINE_PATH"
        guard let s = try? String(contentsOfFile: marker, encoding: .utf8) else { return nil }
        let dir = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dir.isEmpty else { return nil }

        let res = (dir as NSString).appendingPathComponent("deadlinecommand")
        if FileManager.default.isExecutableFile(atPath: res) { return res }

        let bin = (dir as NSString).appendingPathComponent("bin/deadlinecommand")
        if FileManager.default.isExecutableFile(atPath: bin) { return bin }

        return nil
    }

    // MARK: - Pools / Groups
    
    static func fetchLists(deadlineCmd: String) throws -> Lists {
        let pools  = try runAndCollect(deadlineCmd, ["-GetPoolNames"])
        let groups = try runAndCollect(deadlineCmd, ["-GetGroupNames"])
        return Lists(pools: pools, groups: groups)
    }

    // MARK: - Submit FFmpeg job
    
    @discardableResult
    static func submitFFmpegJob(deadlineCmd: String,
                                item: MediaItem,
                                settings: Settings,
                                ffmpegPath: String) -> SubmissionResult {
        let fm = FileManager.default
        let input  = item.url
        let output = item.finalOutputURL ?? OutputNamer.suggestedOutputURL(for: input, settings: settings)

        // Sync metadata (ensure TC/FPS are there)
        var liveItem = item
        if let shared = AppState.shared,
           let cur = shared.files.first(where: { $0.url == item.url }) {
            liveItem.meta.coalesce(with: cur.meta)
        }
        if liveItem.meta.startTimecode == nil || liveItem.meta.nominalFPS == nil {
            let fresh = MetadataExtractor.extract(for: liveItem.url)
            liveItem.meta.coalesce(with: fresh)
            if let shared = AppState.shared,
               let idx = shared.files.firstIndex(where: { $0.url == liveItem.url }) {
                DispatchQueue.main.async { shared.files[idx].meta = liveItem.meta }
            }
        }

        let args = FFmpegCommandBuilder.buildArgs(item: liveItem, output: output, settings: settings)
        let outputArgs = ffmpegOutputArgs(fromFullArgs: args, input: input, output: output)

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MrHEVC_\(UUID().uuidString)", isDirectory: true)

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

            let jobInfoURL    = tmpDir.appendingPathComponent("jobInfo.job")
            let pluginInfoURL = tmpDir.appendingPathComponent("pluginInfo.job")

            try writeFFmpegJobInfo(to: jobInfoURL, input: input, output: output, settings: settings)
            try writeFFmpegPluginInfo(to: pluginInfoURL,
                                      input: input,
                                      output: output,
                                      ffmpegPath: ffmpegPath,
                                      outputArgs: outputArgs)

            let (code, out) = runCLI(path: deadlineCmd,
                                     args: ["-SubmitJob", jobInfoURL.path, pluginInfoURL.path])

            try? fm.removeItem(at: tmpDir)
            return SubmissionResult(input: input, output: output, exitCode: code, rawOutput: out)
        } catch {
            try? fm.removeItem(at: tmpDir)
            return SubmissionResult(input: input, output: output,
                                    exitCode: -1,
                                    rawOutput: "Failed to write/submit Deadline job: \(error)")
        }
    }

    // MARK: - FFmpeg plugin helpers
    
    private static func ffmpegOutputArgs(fromFullArgs full: [String], input: URL, output: URL) -> String {
        var args = full
        if let last = args.last, last == output.path { _ = args.popLast() }
        if let iIdx = args.firstIndex(of: "-i") {
            if iIdx + 1 < args.count && args[iIdx + 1] == input.path {
                args.removeSubrange(iIdx...iIdx+1)
            } else {
                args.remove(at: iIdx)
            }
        }
        args.removeAll { $0 == "-hide_banner" }
        return args.joined(separator: " ")
    }

    private static func writeFFmpegJobInfo(to url: URL, input: URL, output: URL, settings: Settings) throws {
        var lines: [String] = []
        let name = settings.jobName.isEmpty
            ? output.deletingPathExtension().lastPathComponent
            : settings.jobName
        lines.append("Name=\(escapeJobField(name))")
        if !settings.batchName.isEmpty { lines.append("BatchName=\(escapeJobField(settings.batchName))") }
        if !settings.comment.isEmpty   { lines.append("Comment=\(escapeJobField(settings.comment))") }
        if !settings.pool.isEmpty          { lines.append("Pool=\(escapeJobField(settings.pool))") }
        if !settings.secondaryPool.isEmpty { lines.append("SecondaryPool=\(escapeJobField(settings.secondaryPool))") }
        if !settings.group.isEmpty         { lines.append("Group=\(escapeJobField(settings.group))") }
        lines.append("Priority=\(settings.priority)")
        lines.append("Plugin=FFmpeg")
        lines.append("Frames=0")
        lines.append("ChunkSize=1")
        lines.append("OutputDirectory0=\(output.deletingLastPathComponent().path)")
        lines.append("OutputFilename0=\(output.lastPathComponent)")
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func writeFFmpegPluginInfo(to url: URL,
                                              input: URL,
                                              output: URL,
                                              ffmpegPath: String,
                                              outputArgs: String) throws {
        var lines: [String] = []
        lines.append("InputFile0=\(input.path)")
        lines.append("InputArgs0=")
        lines.append("ReplacePadding0=False")
        lines.append("OutputFile=\(output.path)")
        lines.append("OutputArgs=\(outputArgs)")
        lines.append("UseSameInputArgs=False")
        lines.append("AdditionalArgs=")
        lines.append("VideoPreset=")
        lines.append("AudioPreset=")
        lines.append("SubtitlePreset=")
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - CLI utilities
    
    static func runCLI(path: String, args: [String]) -> (Int32, String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = pipe
        do { try task.run() } catch { return (-1, "Failed to launch \(path): \(error)") }
        task.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (task.terminationStatus, out)
    }

    private static func runAndCollect(_ cmd: String, _ args: [String]) throws -> [String] {
        let (code, out) = runCLI(path: cmd, args: args)
        guard code == 0 else {
            throw NSError(domain: "Deadline", code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey: out])
        }
        return out.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func escapeJobField(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Path sanity
    
    static func isInputPathAcceptableForFarm(_ url: URL) -> (ok: Bool, reason: String?) {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let forbidden = [home + "/Desktop", home + "/Downloads"]
        if forbidden.contains(where: { path.hasPrefix($0 + "/") || path == $0 }) {
            return (false, "Path is under \(home)/Desktop or /Downloads; farm nodes won’t see this.")
        }
        if path.hasPrefix(home + "/") && !path.hasPrefix("/Volumes/") {
            return (false, "Path is under your local home folder. Use a shared path (e.g. /Volumes/Share/…).")
        }
        if path.hasPrefix("/Volumes/") { return (true, nil) }
        return (true, nil)
    }

    // MARK: - JobID extraction (for concise success messages)

    /// Try to extract a JobID from Deadline CLI output.
    private static func extractDeadlineJobID(from s: String) -> String? {
        // Common Deadline output shape:
        // "Job submitted successfully: SomeName [62c7d1f9e44adf2b3f35e0c7]"
        if let m = s.range(of: #"\[([0-9a-f]{24})\]"#, options: .regularExpression) {
            return String(s[m]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        // Fallback: first 24-hex token
        if let m = s.range(of: #"[0-9a-f]{24}"#, options: .regularExpression) {
            return String(s[m])
        }
        return nil
    }
}
