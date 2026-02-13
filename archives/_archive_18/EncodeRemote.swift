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
    /// - On success: sets `.queued` with reason "Submitted to Deadline…"
    /// - On failure: sets `.error` with the returned message
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

        // Path to ffmpeg as seen by farm workers (FFmpeg plugin often doesn’t need it, but keep a sane default)
        let ffmpegOnFarm = "/usr/local/bin/ffmpeg"

        DispatchQueue.global(qos: .userInitiated).async {
            for item in items {
                // Skip items actively encoding (leave them alone)
                if item.status == .encoding { continue }

                // Block obviously local-only paths (e.g., Desktop/Downloads) so farm won’t 404
                let okFarm = isInputPathAcceptableForFarm(item.url)
                if !okFarm.ok {
                    DispatchQueue.main.async {
                        if let shared = AppState.shared,
                           let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                            shared.files[idx].status = .blocked
                            shared.files[idx].statusReason = okFarm.reason
                        }
                    }
                    continue
                }

                // Mark as "queued/submitting" while we fire off the submit
                DispatchQueue.main.async {
                    if let shared = AppState.shared,
                       let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                        shared.files[idx].status = .queued
                        shared.files[idx].statusReason = "Submitting to Deadline…"
                    }
                }

                // Submit a single FFmpeg plugin job
                let result = submitFFmpegJob(deadlineCmd: deadlineCmd,
                                             item: item,
                                             settings: settings,
                                             ffmpegPath: ffmpegOnFarm)

                // Reflect the outcome
                DispatchQueue.main.async {
                    guard let shared = AppState.shared,
                          let idx = shared.files.firstIndex(where: { $0.id == item.id }) else { return }

                    if result.exitCode == 0 {
                        // Keep the actual output path we used (prevents “-2” suffix later)
                        shared.files[idx].finalOutputURL = result.output
                        shared.files[idx].status = .queued
                        shared.files[idx].statusReason = "Submitted to Deadline."
                    } else {
                        shared.files[idx].status = .error
                        // Trim noisy output but keep something useful
                        let msg = result.rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                        shared.files[idx].statusReason = msg.isEmpty ? "Deadline submit failed (code \(result.exitCode))."
                                                                     : msg
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

    /// Try the classic marker file used by Deadline installers.
    static func detectDeadlineCommand() -> String? {
        let marker = "/Users/Shared/Thinkbox/DEADLINE_PATH"
        guard let s = try? String(contentsOfFile: marker, encoding: .utf8) else { return nil }
        let dir = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dir.isEmpty else { return nil }

        // Common macOS layout: Resources/deadlinecommand (or bin/deadlinecommand)
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

    // MARK: - Export FFmpeg plugin job bundles to Desktop (no submission)

    /// Writes `*_jobInfo.job` and `*_pluginInfo.job` files per input,
    /// formatted for the **Deadline FFmpeg plugin** (not CommandLine).
    /// Files go to `~/Desktop/MrHEVC Jobs/`.
    @discardableResult
    static func writeFFmpegJobBundlesToDesktop(items: [MediaItem],
                                               settings: Settings,
                                               ffmpegPath: String) throws -> [URL] {
        let fm = FileManager.default
        let desktop = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        let outDir = desktop.appendingPathComponent("MrHEVC Jobs", isDirectory: true)

        if !fm.fileExists(atPath: outDir.path) {
            try fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        }

        var written: [URL] = []

        for item in items {
            let input  = item.url
            // PREFER previous final path for re-queue overwrite; otherwise suggest a new one
            let output = item.finalOutputURL ?? OutputNamer.suggestedOutputURL(for: input, settings: settings)

            // Build full ffmpeg args, then strip input/output for OutputArgs (plugin expects only option flags)
            let args = FFmpegCommandBuilder.buildArgs(item: item, output: output, settings: settings)
            let outputArgs = ffmpegOutputArgs(fromFullArgs: args, input: input, output: output)

            // Base filename for pair
            let baseStem = output.deletingPathExtension().lastPathComponent
            let jobInfoURL    = outDir.appendingPathComponent("\(baseStem)_jobInfo.job")
            let pluginInfoURL = outDir.appendingPathComponent("\(baseStem)_pluginInfo.job")

            try writeFFmpegJobInfo(to: jobInfoURL, input: input, output: output, settings: settings)
            try writeFFmpegPluginInfo(to: pluginInfoURL,
                                      input: input,
                                      output: output,
                                      ffmpegPath: ffmpegPath,
                                      outputArgs: outputArgs)

            written.append(jobInfoURL)
            written.append(pluginInfoURL)
        }

        return written
    }


    // MARK: - (Optional) Submit FFmpeg plugin job now

    /// Submit previously generated FFmpeg plugin job pair to Deadline.
    /// You can call this for each (jobInfo, pluginInfo).
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
        // PREFER previous final path for re-queue overwrite; otherwise suggest a new one
        let output = item.finalOutputURL ?? OutputNamer.suggestedOutputURL(for: input, settings: settings)

        // --- Ensure we build with the freshest metadata (timecode/FPS) ---
        var liveItem = item

        // 1) Pull latest from AppState (UI may have finished async extract)
        if let shared = AppState.shared,
           let cur = shared.files.first(where: { $0.url == item.url }) {
            liveItem.meta = cur.meta
        }

        // 2) Last-chance synchronous extract if TC/FPS are still missing
        if liveItem.meta.startTimecode == nil || liveItem.meta.nominalFPS == nil {
            let fresh = MetadataExtractor.extract(for: liveItem.url)
            if liveItem.meta.startTimecode == nil { liveItem.meta.startTimecode = fresh.startTimecode }
            if liveItem.meta.nominalFPS == nil   { liveItem.meta.nominalFPS   = fresh.nominalFPS }
            // (Optional) coalesce NCLC too so farm jobs get correct tagging
            if liveItem.meta.colorPrimaries == nil   { liveItem.meta.colorPrimaries   = fresh.colorPrimaries }
            if liveItem.meta.transferFunction == nil { liveItem.meta.transferFunction = fresh.transferFunction }
            if liveItem.meta.ycbcrMatrix == nil      { liveItem.meta.ycbcrMatrix      = fresh.ycbcrMatrix }

            // Push back to AppState so UI reflects improvements
            if let shared = AppState.shared,
               let idx = shared.files.firstIndex(where: { $0.url == liveItem.url }) {
                DispatchQueue.main.async { shared.files[idx].meta = liveItem.meta }
            }
        }

        // Build full ffmpeg args, then strip input/output for OutputArgs (plugin expects only option flags)
        let args = FFmpegCommandBuilder.buildArgs(item: liveItem, output: output, settings: settings)
        let outputArgs = ffmpegOutputArgs(fromFullArgs: args, input: input, output: output)

        // Temp working folder
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MrHEVC_\(UUID().uuidString)", isDirectory: true)

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

            // Write the jobInfo / pluginInfo pair for the FFmpeg plugin
            let jobInfoURL    = tmpDir.appendingPathComponent("jobInfo.job")
            let pluginInfoURL = tmpDir.appendingPathComponent("pluginInfo.job")

            try writeFFmpegJobInfo(to: jobInfoURL, input: input, output: output, settings: settings)
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
            // Clean up on failure as well
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

        // Remove trailing output path
        if let last = args.last, last == output.path { _ = args.popLast() }

        // Remove leading -i <input>
        if let iIdx = args.firstIndex(of: "-i") {
            if iIdx + 1 < args.count && args[iIdx + 1] == input.path {
                args.removeSubrange(iIdx...iIdx+1)
            } else {
                args.remove(at: iIdx)
            }
        }

        // The FFmpeg plugin wants a flat string: keep -y, drop only -hide_banner
        args.removeAll { $0 == "-hide_banner" }

        // Join plainly with spaces (no quotes per arg)
        return args.joined(separator: " ")
    }

    /// jobInfo.job for FFmpeg plugin.
    private static func writeFFmpegJobInfo(to url: URL, input: URL, output: URL, settings: Settings) throws {
        var lines: [String] = []

        // Name / batch / comment
        let name = settings.jobName.isEmpty
            ? output.deletingPathExtension().lastPathComponent
            : settings.jobName
        lines.append("Name=\(escapeJobField(name))")
        if !settings.batchName.isEmpty { lines.append("BatchName=\(escapeJobField(settings.batchName))") }
        if !settings.comment.isEmpty   { lines.append("Comment=\(escapeJobField(settings.comment))") }

        // Pools / group / priority
        if !settings.pool.isEmpty          { lines.append("Pool=\(escapeJobField(settings.pool))") }
        if !settings.secondaryPool.isEmpty { lines.append("SecondaryPool=\(escapeJobField(settings.secondaryPool))") }
        if !settings.group.isEmpty         { lines.append("Group=\(escapeJobField(settings.group))") }
        lines.append("Priority=\(settings.priority)")

        // Plugin and minimal framing (single-frame command)
        lines.append("Plugin=FFmpeg")
        lines.append("Frames=0")
        lines.append("ChunkSize=1")

        // Output hints (used by Monitor/UI)
        let outDir  = output.deletingLastPathComponent().path
        let outName = output.lastPathComponent
        lines.append("OutputDirectory0=\(outDir)")
        lines.append("OutputFilename0=\(outName)")

        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// pluginInfo.job for FFmpeg plugin.
    private static func writeFFmpegPluginInfo(to url: URL,
                                              input: URL,
                                              output: URL,
                                              ffmpegPath: String,
                                              outputArgs: String) throws {
        var lines: [String] = []

        // Inputs
        lines.append("InputFile0=\(input.path)")
        lines.append("InputArgs0=")
        lines.append("ReplacePadding0=False")

        // Output (path + only the option args, not input/output)
        lines.append("OutputFile=\(output.path)")
        lines.append("OutputArgs=\(outputArgs)")

        // Common flags in the FFmpeg plugin
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

    private static func runAndCollect(_ cmd: String, _ args: [String]) throws -> [String] {
        let (code, out) = runCLI(path: cmd, args: args)
        guard code == 0 else {
            throw NSError(domain: "Deadline", code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey: out])
        }
        return out
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Local helpers (namespaced to avoid collisions)

    private static func escapeJobField(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shell-escape used for OutputArgs line.
    private static func shellEscapeJobArg(_ s: String) -> String {
        if s.isEmpty { return "''" }
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
    
    // MARK: - Path sanity checks (avoid local-only sources)

    /// Very simple heuristic: block files under the user's Desktop/Downloads (likely inaccessible to farm).
    /// Allow anything under /Volumes (network or external) and other shared paths.
    /// You can relax/tighten this later.
    static func isInputPathAcceptableForFarm(_ url: URL) -> (ok: Bool, reason: String?) {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Disallow Desktop/Downloads outright
        let forbidden = [
            home + "/Desktop",
            home + "/Downloads"
        ]
        if forbidden.contains(where: { path.hasPrefix($0 + "/") || path == $0 }) {
            return (false, "Path is under \(home)/Desktop or /Downloads; farm nodes won’t see this.")
        }

        // If it’s somewhere in the user's home (e.g. Documents), warn unless it's under /Volumes
        if path.hasPrefix(home + "/") && !path.hasPrefix("/Volumes/") {
            return (false, "Path is under your local home folder. Use a shared path (e.g. /Volumes/Share/…).")
        }

        // Accept common shared mount style
        if path.hasPrefix("/Volumes/") {
            return (true, nil)
        }

        // Default allow (you can tighten this later)
        return (true, nil)
    }

}
