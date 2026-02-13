// =============================
// File: EncodeLocal.swift - Fully Non-blocking Version
// =============================
import Foundation
import AVFoundation
import Darwin

private enum TempOut {
    static let q = DispatchQueue(label: "mrhevc.local.tempouts", attributes: .concurrent)
    static var map: [UUID: URL] = [:]   // itemID → temp URL

    static func set(_ url: URL, for id: UUID) {
        q.async(flags: .barrier) { map[id] = url }
    }
    static func get(_ id: UUID) -> URL? {
        q.sync { map[id] }
    }
    static func clear(_ id: UUID) {
        q.async(flags: .barrier) { map.removeValue(forKey: id) }
    }
    static func deleteIfExists(_ id: UUID) {
        if let u = get(id) { try? FileManager.default.removeItem(at: u) }
        clear(id)
    }
}

enum EncodeLocal {

    /// Run local ffmpeg encodes - each item gets its own background thread
    static func run(items: [MediaItem], settings: Settings, ffmpegPath: String? = nil) {
        print("MODE: Local (ffmpeg)")
        print("CRF: \(settings.qualityCRF)  Scale: \(settings.scale.rawValue)  NCLC: \(settings.nclcTag)")

        let ffmpeg = resolveFFmpegPath(ffmpegPath)

        // Process each item in parallel on separate background threads
        for item in items {
            // Skip items that are blocked (shouldn't be processed)
            if item.status == .blocked {
                print("SKIP (blocked): \(item.url.lastPathComponent)")
                continue
            }

            if item.status == .encoding { continue }

            // Launch each encode on its own background thread
            DispatchQueue.global(qos: .userInitiated).async {
                encodeItem(item, settings: settings, ffmpegPath: ffmpeg)
            }
        }
    }

    /// Process a single item (runs on background thread)
    private static func encodeItem(_ item: MediaItem, settings: Settings, ffmpegPath: String) {
        
        // Mark encoding + clear transient fields
        DispatchQueue.main.async {
            AppCore.shared.updateFile(id: item.id) { file in
                file.status = .encoding
                file.statusReason = nil
                file.actualEncodeSeconds = nil
                file.progress = 0
                file.etaSeconds = nil
                file.progressMode = .none
            }
        }

        // Prefer reusing a previous final path (so a re-queue overwrites cleanly)
        let outputURL: URL = {
            if let prev = item.finalOutputURL { return prev }
            
            var result: URL?
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                defer { semaphore.signal() }
                if let shared = AppState.shared,
                   let idx = shared.files.firstIndex(where: { $0.id == item.id }),
                   let prev = shared.files[idx].finalOutputURL {
                    result = prev
                } else {
                    result = OutputNamer.suggestedOutputURL(for: item.url, settings: settings)
                }
            }
            semaphore.wait()
            return result ?? OutputNamer.suggestedOutputURL(for: item.url, settings: settings)
        }()
        
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
            print("ERROR: Could not create output directory: \(error)")
            DispatchQueue.main.async {
                AppCore.shared.updateFile(id: item.id) { file in
                    file.status = .error
                    file.statusReason = "Cannot create output folder"
                }
            }
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
            DispatchQueue.main.async {
                AppCore.shared.updateFile(id: item.id) { file in
                    file.finalOutputURL = outputURL
                    file.status = .done
                    file.statusReason = nil
                    file.actualEncodeSeconds = tagFinish.timeIntervalSince(tagStart)
                    file.progress = nil
                    file.etaSeconds = nil
                    file.progressMode = .none
                }
            }
            // Skip ffmpeg entirely for tag-only case
            return
        }

        // Build ffmpeg args, point to temp file now
        let args = FFmpegCommandBuilder.buildArgs(item: item, output: tempURL, settings: settings)
        print("FFMPEG ARGS for \(item.url.lastPathComponent):")
        print(args.joined(separator: " "))

        // Progress supports real (from known duration) or fake (from wall-time estimator)
        let basics = MediaProbe.readBasics(url: item.url, meta: item.meta, scale: settings.scale)
        if let basics {
            DispatchQueue.main.async {
                AppCore.shared.updateFile(id: item.id) { file in
                    if file.meta.durationSeconds <= 0 {
                        file.meta.durationSeconds = basics.duration
                    }
                    if file.meta.nominalFPS == nil {
                        file.meta.nominalFPS = basics.fps
                    }
                }
            }
        }
        let duration: Double? = basics?.duration ?? (item.meta.durationSeconds > 0 ? item.meta.durationSeconds : nil)
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
        
        // --- Finalize file I/O (off main thread): move temp -> final or delete temp
        var finalizeOK = false
        var finalizeError: String?

        if res.ok {
            do {
                // Replace any pre-existing final, then move temp -> final
                try? FileManager.default.removeItem(at: outputURL)
                try FileManager.default.moveItem(at: tempURL, to: outputURL)
                finalizeOK = true
            } catch {
                // Moving to final failed; delete temp to avoid strays
                finalizeError = "Failed to finalize output: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: tempURL)
            }
        } else {
            // Error or cancel → delete temp
            try? FileManager.default.removeItem(at: tempURL)
        }

        // --- Reflect completion in UI
        DispatchQueue.main.async {
            guard let idx = AppCore.shared.files.firstIndex(where: { $0.id == item.id }) else { return }

            // Unregister the process first
            EncodingService.unregisterProcess(for: item.id)

            if res.cancelled {
                AppCore.shared.updateFile(at: idx) { file in
                    file.status = .queued
                    file.statusReason = "Cancelled by user"
                    file.isChecked = false
                    file.progress = nil
                    file.etaSeconds = nil
                    file.progressMode = .none
                }

                AppState.shared?.pushMessage(
                    level: .info,
                    "Cancelled: process cancelled by user",
                    filename: item.url.lastPathComponent
                )
                return
            }

            if res.ok && finalizeOK {
                AppCore.shared.updateFile(at: idx) { file in
                    file.logURL = res.logURL
                    file.progress = nil
                    file.etaSeconds = nil
                    file.progressMode = .none
                    file.finalOutputURL = outputURL
                    file.status = .done
                    file.statusReason = nil
                    file.actualEncodeSeconds = finishedAt.timeIntervalSince(startedAt)
                    file.isChecked = false
                }

                let updated = AppCore.shared.files[idx]
                let secs = Int(round(updated.actualEncodeSeconds ?? 0))
                let mins = secs / 60
                let rem  = secs % 60

                AppState.shared?.pushMessage(
                    level: .info,
                    "Local encode complete (\(mins)m \(String(format: "%02d", rem))s)",
                    filename: item.url.lastPathComponent,
                    detail: res.tail.isEmpty ? nil : res.tail,
                    logURL: res.logURL
                )

                learnForCompleted(item: updated,
                                  settings: AppCore.shared.settings,
                                  startedAt: startedAt,
                                  finishedAt: finishedAt)
            } else {
                AppCore.shared.updateFile(at: idx) { file in
                    file.logURL = res.logURL
                    file.progress = nil
                    file.etaSeconds = nil
                    file.progressMode = .none
                    file.status = .error
                    file.statusReason = finalizeError ?? "ffmpeg failed"
                }

                AppState.shared?.pushMessage(
                    level: .error,
                    finalizeError ?? "Local encode failed",
                    filename: item.url.lastPathComponent,
                    detail: res.tail.isEmpty ? (finalizeError ?? "ffmpeg exited with an error.") : res.tail,
                    logURL: res.logURL
                )
            }
        }
    }

    // MARK: - Progress-running ffmpeg

    // Launch ffmpeg, drive REAL/FAKE progress from stderr, and capture a tail + full log path.
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

        // MUCH MORE AGGRESSIVE THROTTLING: Only update UI every 2 seconds
        var lastProgressUpdate = Date.distantPast
        let progressUpdateInterval: TimeInterval = 0.3

        // Seed progress mode and (optionally) ETA
        DispatchQueue.main.async {
            AppCore.shared.updateFile(id: item.id) { file in
                if duration != nil {
                    file.progressMode = .real
                    file.progress = 0
                    file.etaSeconds = estimate
                    print("[EncodeLocal] Seed real progress for \(item.url.lastPathComponent) duration=\(duration ?? 0) estimate=\(String(describing: estimate))")
                } else if let est = estimate, est > 0 {
                    file.progressMode = .fake
                    file.progress = 0
                    file.etaSeconds = est
                    print("[EncodeLocal] Seed fake progress for \(item.url.lastPathComponent) est=\(est)")
                } else {
                    file.progressMode = .none
                    file.progress = nil
                    file.etaSeconds = nil
                    print("[EncodeLocal] Seed indeterminate progress for \(item.url.lastPathComponent)")
                }
            }
        }

        let start = Date()

        // Create a temp log file for this session so we can "Reveal Log"
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpeg_\(UUID().uuidString).log")

        // Accumulate stderr so we can return a short tail in UI
        var stderrData = Data()
        let dataQueue = DispatchQueue(label: "ffmpeg.stderr.\(item.id)", qos: .utility)

        // Drain stdout to keep the pipe from clogging - do this asynchronously
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            dataQueue.async {
                _ = handle.availableData // just drain, don't process
            }
        }

        // Parse stderr with HEAVY throttling and async file I/O
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            
            // Do ALL processing on background queue
            dataQueue.async {
                stderrData.append(data)

                // Async file I/O
                if FileManager.default.fileExists(atPath: logURL.path) {
                    if let fh = try? FileHandle(forWritingTo: logURL) {
                        try? fh.seekToEnd()
                        try? fh.write(contentsOf: data)
                        try? fh.close()
                    }
                } else {
                    try? data.write(to: logURL)
                }

                // HEAVY THROTTLING - only process UI updates every 2 seconds
                let now = Date()
                guard now.timeIntervalSince(lastProgressUpdate) >= progressUpdateInterval else { return }
                lastProgressUpdate = now

                guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }

                // REAL mode (known duration): convert media time to WALL ETA via observed speed
                if let range = chunk.range(of: #"time=\d{2}:\d{2}:\d{2}\.\d{2}"#, options: .regularExpression),
                   let total = duration, total > 0 {
                    let token = String(chunk[range]).replacingOccurrences(of: "time=", with: "")
                    let tSec = parseHHMMSS(token)

                    // Progress as media fraction (cap a hair under 100% until exit)
                    let prog = max(0.0, min(0.995, tSec / total))

                    // Observed speed (media sec / wall sec)
                    let elapsed = max(0.0001, Date().timeIntervalSince(start))
                    let speed = max(0.0, tSec / elapsed)

                    // Remaining wall time = remaining media / speed
                    let remainingMedia = max(0, total - tSec)
                    let etaWall = speed > 0 ? (remainingMedia / speed) : remainingMedia

                    // Use async with lowest priority to avoid blocking main thread
                   DispatchQueue.main.async {
                        AppCore.shared.updateFile(id: item.id) { file in
                            file.progressMode = .real
                            file.progress = prog
                            let prior = file.etaSeconds ?? etaWall
                            file.etaSeconds = prior.isFinite ? (0.7 * prior + 0.3 * etaWall) : etaWall
                            print("[EncodeLocal] Real progress \(Int(prog*100))% eta=\(file.etaSeconds ?? 0) for \(item.url.lastPathComponent)")
                        }
                    }

                } else if duration == nil, let est = estimate, est > 0 {
                    // FAKE mode (unknown duration): drive by elapsed / estimate
                    let elapsed = Date().timeIntervalSince(start)
                    let prog = max(0.0, min(0.995, elapsed / est))
                    let remain = max(0.0, est - elapsed)

                   DispatchQueue.main.async {
                        AppCore.shared.updateFile(id: item.id) { file in
                            file.progressMode = .fake
                            file.progress = prog
                            file.etaSeconds = remain
                            print("[EncodeLocal] Fake progress \(Int(prog*100))% eta=\(remain) for \(item.url.lastPathComponent)")
                        }
                    }
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
            
            // Check if process was terminated (cancelled)
            let status = task.terminationStatus
            let reason = task.terminationReason
            cancelled = (reason == .uncaughtSignal)
                || (reason == .exit && (status == SIGTERM || status == SIGKILL))
                || status == SIGTERM || status == SIGKILL
            if EncodingService.consumeCancelled(for: item.id) {
                cancelled = true
            }
            let ok = (task.terminationStatus == 0) && !cancelled
            
            // Wait briefly for async stderr processing to complete
            dataQueue.sync {
                // Just ensuring all stderr data is processed
            }
            
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

    /// Learn from a completed local encode (feeds throughput + size models).
    private static func learnForCompleted(item: MediaItem,
                                          settings: Settings,
                                          startedAt: Date,
                                          finishedAt: Date) {
        EncodeTimeEstimator.recordCompleted(url: item.url,
                                            meta: item.meta,
                                            settings: settings,
                                            runMode: .localFFmpeg,
                                            startedAt: startedAt,
                                            finishedAt: finishedAt)

        // Optional: record output size for size model if file exists
        if let out = item.finalOutputURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: out.path),
           let bytes = attrs[.size] as? NSNumber {
            // If you maintain a size model, hook it here.
            // Example:
            // EncodeStatsStore.shared.recordSizeSample(bytes: bytes.int64Value, …)
            _ = bytes // placeholder to avoid unused warning if not used
        }
    }
}
