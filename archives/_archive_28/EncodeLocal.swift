// =============================
// File: EncodeLocal.swift
// =============================
import Foundation
import AVFoundation

enum EncodeLocal {

    /// Run local ffmpeg encodes sequentially.
    static func run(items: [MediaItem], settings: Settings, ffmpegPath: String? = nil) {
        print("MODE: Local (ffmpeg)")
        print("CRF: \(settings.qualityCRF)  Scale: \(settings.scale.rawValue)  NCLC: \(settings.nclcTag)")

        let ffmpeg = resolveFFmpegPath(ffmpegPath)

        for item in items {
            
            // Skip items that are blocked (shouldn’t be processed)
            if item.status == .blocked {
                print("SKIP (blocked): \(item.url.lastPathComponent)")
                continue
            }

            if item.status == .encoding { continue }

            // Mark encoding + clear transient fields
            DispatchQueue.main.async {
                if let shared = AppState.shared,
                   let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                    shared.files[idx].status = .encoding
                    shared.files[idx].statusReason = nil
                    shared.files[idx].actualEncodeSeconds = nil
                    shared.files[idx].progress = 0
                    shared.files[idx].etaSeconds = nil
                    shared.files[idx].progressMode = .none
                }
            }

            // Prefer reusing a previous final path (so a re-queue overwrites cleanly)
            let outputURL: URL = {
                if let prev = item.finalOutputURL { return prev }
                if let shared = AppState.shared,
                   let idx = shared.files.firstIndex(where: { $0.id == item.id }),
                   let prev = shared.files[idx].finalOutputURL {
                    return prev
                }
                return OutputNamer.suggestedOutputURL(for: item.url, settings: settings)
            }()

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
                    if let shared = AppState.shared,
                       let i = shared.files.firstIndex(where: { $0.id == item.id }) {
                        shared.files[i].status = .error
                        shared.files[i].statusReason = "Cannot create output folder"
                    }
                }
                continue
            }

            // === INSERT: Compressor in-place NCLC tag-only fast path =====================
            let tagStart = Date()
            if CompressorTagger.tryTagOnlyIfEligible(input: item.url,
                                                     output: outputURL,
                                                     settings: settings,
                                                     meta: item.meta,
                                                     log: { print($0) }) {
                let tagFinish = Date()
                DispatchQueue.main.async {
                    if let shared = AppState.shared,
                       let i = shared.files.firstIndex(where: { $0.id == item.id }) {
                        shared.files[i].finalOutputURL = outputURL
                        shared.files[i].status = .done
                        shared.files[i].statusReason = nil
                        shared.files[i].actualEncodeSeconds = tagFinish.timeIntervalSince(tagStart)
                        shared.files[i].progress = nil
                        shared.files[i].etaSeconds = nil
                        shared.files[i].progressMode = .none
                    }
                }
                // Skip ffmpeg entirely for tag-only case
                continue
            }

            // Build ffmpeg args
            let args = FFmpegCommandBuilder.buildArgs(item: item, output: outputURL, settings: settings)
            print("FFMPEG ARGS:")
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
            let res = runWithProgress(executable: ffmpeg,
                                      arguments: args,
                                      for: item,
                                      duration: duration,
                                      estimate: estimate)
            let finishedAt = Date()

            // Reflect completion (replaces the existing block)
            DispatchQueue.main.async {
                guard let shared = AppState.shared,
                      let idx = shared.files.firstIndex(where: { $0.id == item.id }) else { return }

                // Persist the per-item log path for later (UI "Reveal Log", etc.)
                shared.files[idx].logURL = res.logURL

                if res.ok {
                    shared.files[idx].finalOutputURL = outputURL
                    shared.files[idx].status = .done
                    shared.files[idx].statusReason = nil
                    shared.files[idx].actualEncodeSeconds = finishedAt.timeIntervalSince(startedAt)

                    let secs = Int(round(shared.files[idx].actualEncodeSeconds ?? 0))
                    let mins = secs / 60
                    let rem  = secs % 60

                    AppState.shared?.pushMessage(
                        level: .info,
                        "Local encode complete (\(mins)m \(String(format: "%02d", rem))s)",
                        filename: item.url.lastPathComponent,
                        detail: res.tail.isEmpty ? nil : res.tail,
                        logURL: res.logURL
                    )

                    // Update any learning/estimator you maintain
                    learnForCompleted(item: shared.files[idx],
                                      settings: shared.settings,
                                      startedAt: startedAt,
                                      finishedAt: finishedAt)

                    // Uncheck after success (matches your prior behavior)
                    shared.files[idx].isChecked = false
                } else {
                    shared.files[idx].status = .error
                    shared.files[idx].statusReason = "ffmpeg failed"

                    AppState.shared?.pushMessage(
                        level: .error,
                        "Local encode failed",
                        filename: item.url.lastPathComponent,
                        detail: res.tail.isEmpty ? "ffmpeg exited with an error." : res.tail,
                        logURL: res.logURL
                    )
                }

                // Clear transient progress UI
                shared.files[idx].progress = nil
                shared.files[idx].etaSeconds = nil
                shared.files[idx].progressMode = .none
            }
        }
    }

    // MARK: - Progress-running ffmpeg

    // Launch ffmpeg, drive REAL/FAKE progress from stderr, and capture a tail + full log path.
    private static func runWithProgress(executable ffmpeg: String,
                                        arguments args: [String],
                                        for item: MediaItem,
                                        duration: Double?,
                                        estimate: Double?) -> (ok: Bool, tail: String, logURL: URL?)
    {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpeg)
        task.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError  = errPipe

        // Seed progress mode and (optionally) ETA
        DispatchQueue.main.async {
            if let shared = AppState.shared,
               let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                if duration != nil {
                    shared.files[idx].progressMode = .real
                    shared.files[idx].progress = 0
                    // Seed ETA with the estimator if available (replaced once we get first time=)
                    shared.files[idx].etaSeconds = estimate
                } else if let est = estimate, est > 0 {
                    shared.files[idx].progressMode = .fake
                    shared.files[idx].progress = 0
                    shared.files[idx].etaSeconds = est
                } else {
                    shared.files[idx].progressMode = .none
                    shared.files[idx].progress = nil
                    shared.files[idx].etaSeconds = nil
                }
            }
        }

        let start = Date()

        // Drain stdout to keep the pipe from clogging
        outPipe.fileHandleForReading.readabilityHandler = { _ in
            _ = outPipe.fileHandleForReading.availableData
        }

        // Create a temp log file for this session so we can "Reveal Log"
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ffmpeg_\(UUID().uuidString).log")

        // Accumulate stderr so we can return a short tail in UI
        var stderrData = Data()

        // Parse stderr: look for ffmpeg's "time=hh:mm:ss.xx"
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            stderrData.append(data)

            // Append to disk (first write creates file)
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fh = try? FileHandle(forWritingTo: logURL) {
                    try? fh.seekToEnd()
                    try? fh.write(contentsOf: data)
                    try? fh.close()
                }
            } else {
                try? data.write(to: logURL)
            }

            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }

            // REAL mode (known duration): convert media time to WALL ETA via observed speed
            if let range = chunk.range(of: #"time=\d{2}:\d{2}:\d{2}\.\d{2}"#, options: .regularExpression),
               let total = duration, total > 0 {
                let token = String(chunk[range]).replacingOccurrences(of: "time=", with: "")
                let tSec = parseHHMMSS(token)

                // Progress as media fraction (cap a hair under 100% until exit)
                let prog = max(0.0, min(0.995, tSec / total))

                // Observed speed (media sec / wall sec)
                let elapsed = max(0.0001, Date().timeIntervalSince(start)) // avoid div-by-zero
                let speed = max(0.0, tSec / elapsed)

                // Remaining wall time = remaining media / speed
                let remainingMedia = max(0, total - tSec)
                let etaWall = speed > 0 ? (remainingMedia / speed) : remainingMedia

                DispatchQueue.main.async {
                    if let shared = AppState.shared,
                       let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                        shared.files[idx].progressMode = .real
                        shared.files[idx].progress = prog
                        // Light EMA to reduce jitter
                        if let old = shared.files[idx].etaSeconds, old.isFinite {
                            shared.files[idx].etaSeconds = 0.5 * etaWall + 0.5 * old
                        } else {
                            shared.files[idx].etaSeconds = etaWall
                        }
                    }
                }

            } else {
                // FAKE mode (unknown duration): drive by elapsed / estimate
                if duration == nil, let est = estimate, est > 0 {
                    let elapsed = Date().timeIntervalSince(start)
                    let prog = max(0.0, min(0.995, elapsed / est))
                    let remain = max(0.0, est - elapsed)

                    DispatchQueue.main.async {
                        if let shared = AppState.shared,
                           let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                            shared.files[idx].progressMode = .fake
                            shared.files[idx].progress = prog
                            shared.files[idx].etaSeconds = remain
                        }
                    }
                }
            }
        }

        do {
            defer {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
            }
            try task.run()
            task.waitUntilExit()
            let ok = (task.terminationStatus == 0)
            let tailData = stderrData.count > 4096 ? stderrData.suffix(4096) : stderrData
            let tail = String(data: tailData, encoding: .utf8) ?? ""
            return (ok, tail, logURL)
        } catch {
            let msg = "Failed to launch ffmpeg: \(error)"
            try? msg.data(using: .utf8)?.write(to: logURL)
            return (false, msg, logURL)
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
