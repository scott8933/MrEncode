// =============================
// File: EncodeLocal.swift - AppCore-boundary version (no AppState.shared usage)
// =============================
import Foundation
import AVFoundation

private enum TempOut {
    static let q = DispatchQueue(label: "mrhevc.local.tempouts", attributes: .concurrent)
    static var map: [UUID: URL] = [:]   // itemID → temp URL

    static func set(_ url: URL, for id: UUID) {
        q.async(flags: .barrier) { map[id] = url }
    }
    static func get(_ id: UUID) -> URL? { q.sync { map[id] } }
    static func clear(_ id: UUID) {
        q.async(flags: .barrier) { map.removeValue(forKey: id) }
    }
    static func deleteIfExists(_ id: UUID) {
        if let u = get(id) { try? FileManager.default.removeItem(at: u) }
        clear(id)
    }
}

enum EncodeLocal {

    /// Run local ffmpeg encodes — each item gets its own background thread.
    static func run(items: [MediaItem], settings: Settings, ffmpegPath: String? = nil) {
        print("MODE: Local (ffmpeg)")
        print("CRF: \(settings.qualityCRF)  Scale: \(settings.scale.rawValue)  NCLC: \(settings.nclcTag)")

        let ffmpeg = resolveFFmpegPath(ffmpegPath)

        // Process each item in parallel on separate background threads
        for item in items {
            // Skip items that are blocked or already encoding
            guard item.status != .blocked, item.status != .encoding else {
                if item.status == .blocked {
                    print("SKIP (blocked): \(item.url.lastPathComponent)")
                }
                continue
            }

            DispatchQueue.global(qos: .userInitiated).async {
                encodeItem(item, settings: settings, ffmpegPath: ffmpeg)
            }
        }
    }

    /// Process a single item (runs on background thread)
    private static func encodeItem(_ item: MediaItem, settings: Settings, ffmpegPath: String) {

        // Mark encoding + reset transient progress fields
        AppCore.shared.setStatus(id: item.id, .encoding)
        AppCore.shared.setProgress(id: item.id, 0.0)
        AppCore.shared.appendLog(level: .info,
                                 "Starting encode",
                                 filename: item.url.lastPathComponent)

        // Prefer reusing a previous final path (so a re-queue overwrites cleanly)
        let outputURL: URL = item.finalOutputURL
            ?? OutputNamer.suggestedOutputURL(for: item.url, settings: settings)

        // Temp file next to final
        let tempURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".tmp-\(UUID().uuidString)-\(outputURL.lastPathComponent)")

        TempOut.set(tempURL, for: item.id)

        // Ensure output directory exists
        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            let msg = "Cannot create output folder: \(error.localizedDescription)"
            print("ERROR: \(msg)")
            AppCore.shared.setStatus(id: item.id, .error, reason: "Cannot create output folder")
            AppCore.shared.appendLog(level: .error,
                                     "Local encode failed",
                                     filename: item.url.lastPathComponent,
                                     detail: msg)
            TempOut.deleteIfExists(item.id)
            return
        }

        // === Compressor in-place NCLC tag-only fast path =====================
        let tagStart = Date()
        if CompressorTagger.tryTagOnlyIfEligible(input: item.url,
                                                 output: outputURL,
                                                 settings: settings,
                                                 meta: item.meta,
                                                 log: { print($0) }) {
            let tagFinish = Date()
            // Commit results
            AppCore.shared.setFinalOutput(id: item.id, outputURL)
            AppCore.shared.setStatus(id: item.id, .done)
            AppCore.shared.appendLog(level: .info,
                                     "Local tag-only complete (\(formatElapsed(tagFinish.timeIntervalSince(tagStart))) )",
                                     filename: item.url.lastPathComponent)

            TempOut.deleteIfExists(item.id)
            return
        }

        // Build ffmpeg args, point to temp file now
        let args = FFmpegCommandBuilder.buildArgs(item: item, output: tempURL, settings: settings)
        print("FFMPEG ARGS for \(item.url.lastPathComponent):")
        print(args.joined(separator: " "))

        // Progress supports real (from known duration) or fake (from wall-time estimator)
        let duration = item.meta.durationSeconds
        let estimate = EncodeTimeEstimator.estimateSeconds(
            url: item.url,
            meta: item.meta,
            settings: settings,
            runMode: .localFFmpeg
        )

        let startedAt = Date()
        let res = runWithProgress(executable: ffmpegPath,
                                  arguments: args,
                                  for: item,
                                  duration: duration,
                                  estimate: estimate)
        let finishedAt = Date()

        // Finalize file I/O (off main thread): move temp -> final or delete temp
        var finalizeOK = false
        var finalizeError: String?

        if res.ok {
            do {
                // Replace any pre-existing final, then move temp -> final
                try? FileManager.default.removeItem(at: outputURL)
                try FileManager.default.moveItem(at: tempURL, to: outputURL)
                finalizeOK = true
            } catch {
                finalizeError = "Failed to finalize output: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: tempURL)
            }
        } else {
            // Error or cancel → delete temp
            try? FileManager.default.removeItem(at: tempURL)
        }

        TempOut.clear(item.id)

        // Reflect completion
        if res.cancelled {
            AppCore.shared.remove(id: item.id)
            AppCore.shared.appendLog(level: .info,
                                     "Local encode cancelled",
                                     filename: item.url.lastPathComponent)
            return
        }

        if res.ok && finalizeOK {
            AppCore.shared.setFinalOutput(id: item.id, outputURL)
            AppCore.shared.setStatus(id: item.id, .done)

            // Update estimator learning
            EncodeTimeEstimator.recordCompleted(url: item.url,
                                                meta: item.meta,
                                                settings: settings,
                                                runMode: .localFFmpeg,
                                                startedAt: startedAt,
                                                finishedAt: finishedAt)

            AppCore.shared.appendLog(level: .info,
                                     "Local encode complete (\(formatElapsed(finishedAt.timeIntervalSince(startedAt))))",
                                     filename: item.url.lastPathComponent)
            // If you want to uncheck after success, use:
            // AppCore.shared.toggleQueued(id: item.id, isQueued: false)
        } else {
            // Either ffmpeg failed OR the finalize move failed
            let detail = res.tail.isEmpty ? (finalizeError ?? "ffmpeg exited with an error.") : res.tail
            AppCore.shared.setStatus(id: item.id, .error, reason: finalizeError ?? "ffmpeg failed")
            AppCore.shared.appendLog(level: .error,
                                     finalizeError ?? "Local encode failed",
                                     filename: item.url.lastPathComponent,
                                     detail: detail)
        }

        // Clear progress visual (progress becomes nil once done/failed)
        AppCore.shared.setProgress(id: item.id, nil)
    }

    // MARK: - Progress-running ffmpeg

    /// Launch ffmpeg, drive REAL/FAKE progress from stderr, and capture a tail + full log path.
    private static func runWithProgress(executable ffmpeg: String,
                                        arguments args: [String],
                                        for item: MediaItem,
                                        duration: Double?,
                                        estimate: Double?) -> (ok: Bool, cancelled: Bool, tail: String, logURL: URL?)
    {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpeg)
        task.arguments = args

        // Register process for cancellation
        EncodingService.registerProcess(task, for: item.id)

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError  = errPipe

        // Throttle UI progress updates to avoid jank
        var lastProgressUpdate = Date.distantPast
        let progressUpdateInterval: TimeInterval = 2.0

        // Seed initial progress
        if duration != nil || (estimate ?? 0) > 0 {
            AppCore.shared.setProgress(id: item.id, 0.0)
        } else {
            AppCore.shared.setProgress(id: item.id, nil)
        }

        let start = Date()

        // Create a temp log file for this session so we can "Reveal Log" (if wired later)
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpeg_\(UUID().uuidString).log")

        // Accumulate stderr so we can return a short tail in UI
        var stderrData = Data()
        let dataQueue = DispatchQueue(label: "ffmpeg.stderr.\(item.id)", qos: .utility)

        // Drain stdout to keep the pipe from clogging
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            dataQueue.async { _ = handle.availableData }
        }

        // Parse stderr with throttling and async file I/O
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }

            dataQueue.async {
                stderrData.append(data)

                // Append to log file asynchronously
                if FileManager.default.fileExists(atPath: logURL.path) {
                    if let fh = try? FileHandle(forWritingTo: logURL) {
                        try? fh.seekToEnd()
                        try? fh.write(contentsOf: data)
                        try? fh.close()
                    }
                } else {
                    try? data.write(to: logURL)
                }

                // Only process UI updates every N seconds
                let now = Date()
                guard now.timeIntervalSince(lastProgressUpdate) >= progressUpdateInterval else { return }
                lastProgressUpdate = now

                guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }

                // REAL mode (known duration): parse "time=HH:MM:SS.xx"
                if let range = chunk.range(of: #"time=\d{2}:\d{2}:\d{2}\.\d{2}"#, options: .regularExpression),
                   let total = duration, total > 0 {
                    let token = String(chunk[range]).replacingOccurrences(of: "time=", with: "")
                    let tSec = parseHHMMSS(token)

                    // Progress as media fraction (cap under 100% until exit)
                    let prog = max(0.0, min(0.995, tSec / total))

                    // Observed speed (media sec / wall sec)
                    let elapsed = max(0.0001, Date().timeIntervalSince(start))
                    let speed = max(0.0, tSec / elapsed)

                    // Remaining wall time = remaining media / speed
                    let remainingMedia = max(0, total - tSec)
                    _ = speed // currently unused; ETA handled by UI estimator

                    // Publish progress (jitter-smoothing handled by UI/estimator)
                    AppCore.shared.setProgress(id: item.id, prog)

                } else if duration == nil, let est = estimate, est > 0 {
                    // FAKE mode (unknown duration): drive by elapsed / estimate
                    let elapsed = Date().timeIntervalSince(start)
                    let prog = max(0.0, min(0.995, elapsed / est))
                    AppCore.shared.setProgress(id: item.id, prog)
                }
            }
        }

        var cancelled = false

        do {
            defer {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
            }
            try task.run()
            task.waitUntilExit()

            cancelled = (task.terminationReason == .uncaughtSignal)
            let ok = (task.terminationStatus == 0) && !cancelled

            // Wait for async stderr processing to flush
            dataQueue.sync { /* drain */ }

            let tailData = stderrData.count > 4096 ? stderrData.suffix(4096) : stderrData
            let tail = String(data: tailData, encoding: .utf8) ?? ""
            return (ok, cancelled, tail, logURL)
        } catch {
            let msg = "Failed to launch ffmpeg: \(error)"
            try? msg.data(using: .utf8)?.write(to: logURL)
            return (false, false, msg, logURL)
        }
    }

    // MARK: - Helpers

    private static func resolveFFmpegPath(_ override: String?) -> String {
        if let o = override, !o.isEmpty { return o }
        // Try common Homebrew paths first
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",  // Apple Silicon
            "/usr/local/bin/ffmpeg"      // Intel / older setups
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        // Last resort: rely on PATH
        if let which = try? runAndCapture("/usr/bin/which", ["ffmpeg"]).trimmingCharacters(in: .whitespacesAndNewlines),
           !which.isEmpty {
            return which
        }
        return "ffmpeg" // hope it's on PATH
    }

    private static func runAndCapture(_ cmd: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Parse "HH:MM:SS.xx" → seconds (Double)
    private static func parseHHMMSS(_ s: String) -> Double {
        let parts = s.split(separator: ":").map(String.init)
        guard parts.count == 3 else { return 0 }
        let h = Double(parts[0]) ?? 0
        let m = Double(parts[1]) ?? 0
        let sec = Double(parts[2]) ?? 0
        return h * 3600 + m * 60 + sec
    }

    private static func formatElapsed(_ secs: TimeInterval) -> String {
        if secs < 1.0 { return String(format: "%.2f sec", secs) }
        if secs < 60.0 { return String(format: "%.1f sec", secs) }
        let total = Int(round(secs))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = (total % 60)
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
