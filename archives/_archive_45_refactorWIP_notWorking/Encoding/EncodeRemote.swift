// =============================
// File: EncodeRemote.swift  — AppCore-boundary version (no AppState.shared usage)
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
        // Resolve deadlinecommand early (either user-specified or PATH)
        let deadlineCmd = detectDeadlineCommand(preferredPath: settings.deadlineCommandPath)

        // Pre-flight: mark "Submitting…" (indeterminate) for each candidate
        DispatchQueue.main.async {
            for item in items where item.status != .encoding && item.status != .blocked {
                AppCore.shared.setStatus(id: item.id, .encoding, reason: "Submitting to Deadline…")
                AppCore.shared.setProgress(id: item.id, nil) // indeterminate
                // Optional parity with prior behavior: uncheck to prevent double-submit
                // AppCore.shared.toggleQueued(id: item.id, isQueued: false)
            }
        }

        // Submit sequentially (keeps logs/order predictable and avoids bursts)
        DispatchQueue.global(qos: .userInitiated).async {
            for item in items where item.status != .encoding && item.status != .blocked {
                // 1) Shared-path suitability check (guard farm accessibility)
                let okFarm = isInputPathAcceptableForFarm(item.url)
                if !okFarm.ok {
                    AppCore.shared.setStatus(id: item.id, .blocked, reason: okFarm.reason ?? "Path not suitable for farm access")
                    AppCore.shared.setProgress(id: item.id, nil)
                    AppCore.shared.appendLog(level: .warning,
                                             okFarm.reason ?? "Path not suitable for farm access",
                                             filename: item.url.lastPathComponent,
                                             code: .farmPath,
                                             originKey: "deadline-farm-path",
                                             detail: "Path: \(item.url.path)")
                    continue
                }

                // 2) Build & submit FFmpeg job (always submit; no export-only mode in Settings)
                let result = submitFFmpegJob(deadlineCmd: deadlineCmd,
                                             item: item,
                                             settings: settings,
                                             exportOnly: false)

                // 3) Reflect outcome
                if result.exitCode == 0 {
                    // Submission path: attempt to extract JobID from output
                    let jobID = extractJobID(from: result.rawOutput)
                    AppCore.shared.setStatus(id: item.id, .queued, reason: "Submitted to Deadline")
                    AppCore.shared.appendLog(level: .info,
                                             jobID != nil ? "Submitted to Deadline (JobID: \(jobID!))" : "Submitted to Deadline",
                                             filename: item.url.lastPathComponent,
                                             originKey: "deadline-submit",
                                             detail: result.rawOutput)
                } else {
                    // Failed submission
                    AppCore.shared.setStatus(id: item.id, .error, reason: "Deadline submission failed")
                    AppCore.shared.appendLog(level: .error,
                                             "Remote submission failed",
                                             filename: item.url.lastPathComponent,
                                             originKey: "deadline-submit",
                                             detail: result.rawOutput)
                }

                // Small spacing to avoid hammering command repeatedly
                Thread.sleep(forTimeInterval: 0.10)
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

    /// Resolve the deadlinecommand path either from user preference or PATH.
    static func detectDeadlineCommand(preferredPath: String?) -> String {
        if let p = preferredPath, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return p
        }
        // Common Thinkbox Deadline 10 locations (macOS)
        let candidates = [
            "/Applications/Thinkbox/Deadline10/Resources/bin/deadlinecommand",
            "/usr/local/bin/deadlinecommand",
            "/opt/Thinkbox/Deadline10/bin/deadlinecommand"
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        // PATH fallback
        if let which = try? runCLI(path: "/usr/bin/which", args: ["deadlinecommand"]),
           which.exit == 0 {
            let path = which.out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { return path }
        }
        return "deadlinecommand" // hope it's on PATH
    }

    // MARK: - Pools/Groups

    static func fetchPoolsAndGroups(deadlineCmd: String) -> Lists {
        var pools: [String] = []
        var groups: [String] = []

        let poolsOut = runCLI(path: deadlineCmd, args: ["-GetPoolNames"])
        if poolsOut.exit == 0 {
            pools = poolsOut.out
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let groupsOut = runCLI(path: deadlineCmd, args: ["-GetGroupNames"])
        if groupsOut.exit == 0 {
            groups = groupsOut.out
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return Lists(pools: pools, groups: groups)
    }

    // MARK: - Farm path suitability

    /// Enforces that input/destination paths are visible to farm machines.
    /// Disallows common "local-only" locations like Desktop/Downloads and user home paths.
    static func isInputPathAcceptableForFarm(_ url: URL) -> (ok: Bool, reason: String?) {
        let p = url.path
        let low = p.lowercased()

        // Disallow Desktop/Downloads/tmp-ish locations
        if low.contains("/desktop/") || low.hasSuffix("/desktop") {
            return (false, "Desktop is not visible to farm machines; choose a shared volume.")
        }
        if low.contains("/downloads/") || low.hasSuffix("/downloads") {
            return (false, "Downloads is not visible to farm machines; choose a shared volume.")
        }
        if low.contains("/private/tmp/") || low.contains("/tmp/") {
            return (false, "Temporary folders are not suitable for farm access.")
        }

        // Disallow home-bound local paths unless on a mounted /Volumes share
        if low.hasPrefix("/users/") && !low.hasPrefix("/volumes/") {
            return (false, "User home paths are not shared with the farm; use a /Volumes share.")
        }

        // Encourage explicit /Volumes or network mounts
        if !low.hasPrefix("/volumes/") && !low.hasPrefix("/network/") {
            return (false, "Use a shared mount (e.g., /Volumes/YourShare) visible to the farm.")
        }
        return (true, nil)
    }

    // MARK: - Submission

    /// Build and submit an FFmpeg plugin job. If `exportOnly == true`, writes the bundle to Desktop instead of submitting.
    static func submitFFmpegJob(deadlineCmd: String,
                                item: MediaItem,
                                settings: Settings,
                                exportOnly: Bool) -> SubmissionResult
    {
        // 1) Build FFmpeg CLI for *this item* (temp output path is fine; the farm writes final output)
        let outputURL: URL = item.finalOutputURL
            ?? OutputNamer.suggestedOutputURL(for: item.url, settings: settings)

        let fullArgs = FFmpegCommandBuilder.buildArgs(item: item, output: outputURL, settings: settings)
        let pluginLine = ffmpegOutputArgs(fromFullArgs: fullArgs, input: item.url, output: outputURL)

        // 2) Write Deadline job/plugin info to a temp dir (or Desktop for export-only)
        let fm = FileManager.default
        let baseName = item.url.deletingPathExtension().lastPathComponent
        let bundleName = "FFmpeg_\(baseName)_\(UUID().uuidString.prefix(8))"

        let tmpDir: URL
        if exportOnly {
            // Place on Desktop in a folder
            tmpDir = (fm.urls(for: .desktopDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory)
                .appendingPathComponent(bundleName, isDirectory: true)
        } else {
            tmpDir = fm.temporaryDirectory.appendingPathComponent(bundleName, isDirectory: true)
        }

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let (jobInfoURL, pluginInfoURL) = try writeFFmpegJobFiles(
                baseDir: tmpDir,
                item: item,
                settings: settings,
                ffmpegPluginCmd: pluginLine
            )

            if exportOnly {
                // Leave the bundle on Desktop and return success
                return SubmissionResult(input: item.url, output: outputURL, exitCode: 0,
                                        rawOutput: "Exported: \(tmpDir.path)")
            }

            // 3) Submit via deadlinecommand
            let (code, out) = runCLI(path: deadlineCmd,
                                     args: ["-SubmitJob", jobInfoURL.path, pluginInfoURL.path])

            try? fm.removeItem(at: tmpDir)  // clean up temp bundle
            return SubmissionResult(input: item.url, output: outputURL, exitCode: code, rawOutput: out)
        } catch {
            // Cleanup best-effort
            try? fm.removeItem(at: tmpDir)
            return SubmissionResult(input: item.url, output: outputURL,
                                    exitCode: -1,
                                    rawOutput: "Failed to write/submit Deadline job: \(error)")
        }
    }

    // MARK: - FFmpeg plugin helpers

    /// Convert a full ffmpeg CLI into the single-line value Deadline's FFmpeg plugin expects in Plugin Info.
    private static func ffmpegOutputArgs(fromFullArgs full: [String], input: URL, output: URL) -> String {
        var args = full

        // Remove the executable name if present
        if let first = args.first, first.contains("ffmpeg") { args.removeFirst() }

        // Remove -hide_banner if present
        args.removeAll { $0 == "-hide_banner" }

        // Remove the input file (-i <path>) if present
        if let iIdx = args.firstIndex(of: "-i") {
            if iIdx + 1 < args.count {
                // Drop "-i" and its argument (regardless of exact path spelling)
                args.remove(at: iIdx) // "-i"
                if iIdx < args.count { args.remove(at: iIdx) } // path
            }
        }

        // Force input to the farm-visible path
        // (Deadline FFmpeg plugin will prepend ffmpeg and add "-i <input>" automatically if configured so.)
        // Ensure output path stays as computed `output`
        // NOTE: If your plugin requires explicit "-i", include it here per farm config:
        // args = ["-i", input.path] + args

        // Swap any remaining explicit output path tokens with the final `output` path
        // (Some pipelines pass "-y <output>" at the end; ensure it points to `output`.)
        if let outIdx = args.lastIndex(where: { $0.hasSuffix(".mov") || $0.hasSuffix(".mp4") }) {
            args[outIdx] = output.path
        } else {
            // If no explicit output found, append it
            args.append(output.path)
        }

        return args.joined(separator: " ")
    }

    // MARK: - CLI helpers

    @discardableResult
    private static func runCLI(path: String, args: [String]) -> (exit: Int32, out: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args

        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = outPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (-1, "Failed to run \(path): \(error)")
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus, out)
    }

    // MARK: - Plugin jobInfo/pluginInfo writers

    private static func writeFFmpegJobFiles(baseDir: URL,
                                            item: MediaItem,
                                            settings: Settings,
                                            ffmpegPluginCmd: String) throws -> (jobInfo: URL, pluginInfo: URL)
    {
        let fm = FileManager.default
        let jobInfoURL = baseDir.appendingPathComponent("job_info.job")
        let pluginInfoURL = baseDir.appendingPathComponent("plugin_info.job")

        // --- Job Info ---
        var jobInfo: [String] = []
        jobInfo.append("Plugin=FFmpeg")
        // Name (prefer Settings.jobName if set; fall back to baseName-HEVC)
        let baseName = item.url.deletingPathExtension().lastPathComponent
        let name = settings.jobName.trimmed.isEmpty ? "\(baseName)-HEVC" : settings.jobName
        jobInfo.append("Name=\(name)")

        // Optional job metadata
        if !settings.comment.trimmed.isEmpty {
            jobInfo.append("Comment=\(settings.comment)")
        }
        if !settings.batchName.trimmed.isEmpty {
            jobInfo.append("BatchName=\(settings.batchName)")
        }
        if !settings.dependencies.trimmed.isEmpty {
            // Deadline expects comma-separated Job IDs for dependencies
            jobInfo.append("JobDependencies=\(settings.dependencies)")
        }

        // Pool/Group
        if !settings.pool.trimmed.isEmpty        { jobInfo.append("Pool=\(settings.pool)") }
        if !settings.secondaryPool.trimmed.isEmpty { jobInfo.append("SecondaryPool=\(settings.secondaryPool)") }
        if !settings.group.trimmed.isEmpty       { jobInfo.append("Group=\(settings.group)") }

        // Priority
        let prio = max(0, min(100, settings.priority))
        jobInfo.append("Priority=\(prio)")

        // --- Plugin Info ---
        var pluginInfo: [String] = []
        // Command line (without the "ffmpeg" executable)
        pluginInfo.append("Arguments=\(ffmpegPluginCmd)")
        // Explicit input/output (depending on your farm FFmpeg plugin expectations)
        pluginInfo.append("InputFile=\(item.url.path)")
        let outURL: URL = item.finalOutputURL
            ?? OutputNamer.suggestedOutputURL(for: item.url, settings: settings)
        pluginInfo.append("OutputFile=\(outURL.path)")
        // Environment (optional)
        // pluginInfo.append("EnvironmentKeyValue0=...")

        let jobStr = jobInfo.joined(separator: "\n") + "\n"
        let pluginStr = pluginInfo.joined(separator: "\n") + "\n"

        try jobStr.write(to: jobInfoURL, atomically: true, encoding: .utf8)
        try pluginStr.write(to: pluginInfoURL, atomically: true, encoding: .utf8)

        return (jobInfoURL, pluginInfoURL)
    }

    // MARK: - Output parsing

    private static func extractJobID(from output: String) -> String? {
        // Typical Deadline output line:
        // "JobID=68562f81b11a2c2a8a881057"
        for line in output.split(whereSeparator: \.isNewline) {
            let s = String(line)
            if let r = s.range(of: #"JobID=([A-Fa-f0-9]+)"#, options: .regularExpression) {
                let id = String(s[r]).replacingOccurrences(of: "JobID=", with: "")
                return id
            }
        }
        return nil
    }
}
