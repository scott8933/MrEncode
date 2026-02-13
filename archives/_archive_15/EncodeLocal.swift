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
            guard FileManager.default.fileExists(atPath: item.url.path) else { continue }

            // Update status → encoding
            DispatchQueue.main.async {
                if let shared = AppState.shared,
                   let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                    shared.files[idx].status = .encoding
                    shared.files[idx].statusReason = nil
                    shared.files[idx].progress = 0
                    shared.files[idx].progressMode = .fake
                }
            }

            // Output path: prefer an existing finalOutputURL to avoid “-2” suffixes across retries
            let outputURL = item.finalOutputURL ?? OutputNamer.suggestedOutputURL(for: item.url, settings: settings)

            // Build args
            let args = FFmpegCommandBuilder.buildArgs(item: item, output: outputURL, settings: settings)

            print("FFMPEG ARGS:")
            print(args.joined(separator: " "))

            // Progress supports real (from duration) or fake (from estimator)
            let duration = item.meta.durationSeconds
            let estimate = EncodeTimeEstimator.estimateSeconds(
                url: item.url,
                meta: item.meta,
                settings: settings,
                runMode: .localFFmpeg
            )

            DispatchQueue.main.async {
                AppState.shared?.log(.info, "Starting ffmpeg…", fileURL: item.url)
            }
            let startedAt = Date()
            let result = runWithProgress(
                executable: ffmpeg,
                arguments: args,
                for: item,
                duration: duration,
                estimate: estimate
            )
            let finishedAt = Date()

            DispatchQueue.main.async {
                guard let shared = AppState.shared,
                      let idx = shared.files.firstIndex(where: { $0.id == item.id }) else { return }

                if result.ok {
                    shared.files[idx].finalOutputURL = outputURL
                    shared.files[idx].status = .done
                    shared.files[idx].statusReason = nil
                    shared.files[idx].actualEncodeSeconds = finishedAt.timeIntervalSince(startedAt)

                    // ✅ Correct string interpolation (no escaped quotes)
                    let secs = String(format: "%.1fs", finishedAt.timeIntervalSince(startedAt))
                    AppState.shared?.log(.info, "Done in \(secs) → \(outputURL.lastPathComponent)", fileURL: item.url)

                } else {
                    shared.files[idx].status = .error
                    shared.files[idx].statusReason = "ffmpeg failed"
                    let tail = result.stderrTail.split(separator: "\n").suffix(6).joined(separator: "\n")
                    AppState.shared?.log(.error, "ffmpeg failed. \(tail)", fileURL: item.url, autoReveal: true)
                }

                // Clear progress UI
                shared.files[idx].progress = nil
                shared.files[idx].etaSeconds = nil
                shared.files[idx].progressMode = .none
            }
        }
    }

    // MARK: - Resolve ffmpeg path

    private static func resolveFFmpegPath(_ override: String?) -> String {
        if let p = override, !p.isEmpty { return p }
        // Try PATH-resolved, else common Homebrew path
        if let pathFF = which("ffmpeg") { return pathFF }
        return "/opt/homebrew/bin/ffmpeg"
    }

    private static func which(_ cmd: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [cmd]
        let pipe = Pipe()
        task.standardOutput = pipe
        do { try task.run() } catch { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    // MARK: - Progress-running ffmpeg

    private static func runWithProgress(executable ffmpeg: String,
                                        arguments args: [String],
                                        for item: MediaItem,
                                        duration: Double?,
                                        estimate: Double?) -> (ok: Bool, stderrTail: String)
    {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpeg)
        task.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError  = errPipe

        DispatchQueue.main.async {
            if let shared = AppState.shared,
               let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                if let total = duration, total > 0 {
                    shared.files[idx].progressMode = .real
                    shared.files[idx].progress = 0
                    shared.files[idx].etaSeconds = max(0, total)
                } else if let est = estimate, est > 0 {
                    shared.files[idx].progressMode = .fake
                    shared.files[idx].progress = 0
                    shared.files[idx].etaSeconds = max(0, est)
                } else {
                    shared.files[idx].progressMode = .none
                    shared.files[idx].progress = nil
                    shared.files[idx].etaSeconds = nil
                }
            }
        }

        let start = Date()

        var stderrTail = ""
        func appendTail(_ s: String) {
            stderrTail.append(s)
            if stderrTail.count > 4000 {
                stderrTail.removeFirst(stderrTail.count - 4000)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            appendTail(chunk)

            // time=HH:MM:SS(.fraction)
            if let range = chunk.range(of: #"time=\d{2}:\d{2}:\d{2}(?:\.\d+)?"#, options: .regularExpression) {
                let token = String(chunk[range]).replacingOccurrences(of: "time=", with: "")
                let tSec = parseHHMMSS(token)
                if let total = duration, total > 0 {
                    let prog = max(0.0, min(0.995, tSec / total))
                    DispatchQueue.main.async {
                        if let shared = AppState.shared,
                           let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                            shared.files[idx].progressMode = .real
                            shared.files[idx].progress = prog
                            shared.files[idx].etaSeconds = max(0, total - tSec)
                        }
                    }
                } else if let est = estimate, est > 0 {
                    // fallback: a simple time-based pseudo-progress
                    let elapsed = Date().timeIntervalSince(start)
                    let prog = max(0.0, min(0.995, elapsed / est))
                    DispatchQueue.main.async {
                        if let shared = AppState.shared,
                           let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                            shared.files[idx].progressMode = .fake
                            shared.files[idx].progress = prog
                            shared.files[idx].etaSeconds = max(0, est - elapsed)
                        }
                    }
                }
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = { _ in
            _ = outPipe.fileHandleForReading.availableData
        }

        do {
            defer {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
            }
            try task.run()
            task.waitUntilExit()
            return (task.terminationStatus == 0, stderrTail)
        } catch {
            print("Failed to launch ffmpeg: \(error)")
            return (false, stderrTail)
        }
    }

    // MARK: - Utilities

    /// Parse "HH:MM:SS.xx" to seconds
    private static func parseHHMMSS(_ s: String) -> Double {
        let parts = s.split(separator: ":")
        guard parts.count == 3 else { return 0 }
        let h = Double(parts[0]) ?? 0
        let m = Double(parts[1]) ?? 0
        let ssec = Double(parts[2]) ?? 0
        return h * 3600 + m * 60 + ssec
    }
}
