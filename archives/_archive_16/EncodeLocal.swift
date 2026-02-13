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
            if item.status == .encoding { continue }

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

            // Reuse previous final URL (overwrite) if present; else suggest a new one.
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
                        shared.log(.error, "Cannot create output folder.", fileURL: item.url, autoReveal: true)
                    }
                }
                continue
            }

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

            let startedAt = Date()
            let ok = runWithProgress(executable: ffmpeg,
                                     arguments: args,
                                     for: item,
                                     duration: duration,
                                     estimate: estimate)
            let finishedAt = Date()

            DispatchQueue.main.async {
                guard let shared = AppState.shared,
                      let idx = shared.files.firstIndex(where: { $0.id == item.id }) else { return }

                if ok {
                    shared.files[idx].finalOutputURL = outputURL
                    shared.files[idx].status = .done
                    shared.files[idx].statusReason = nil
                    shared.files[idx].actualEncodeSeconds = finishedAt.timeIntervalSince(startedAt)

                    // concise success line
                    shared.log(.info, "Done.", fileURL: item.url)

                    // Record speed + size stats (to improve future estimates).
                    learnForCompleted(item: shared.files[idx],
                                      settings: shared.settings,
                                      startedAt: startedAt,
                                      finishedAt: finishedAt)

                } else {
                    shared.files[idx].status = .error
                    shared.files[idx].statusReason = "ffmpeg failed"
                    // (Error already logged inside runWithProgress; keep UI status only here.)
                }

                // Clear progress UI
                shared.files[idx].progress = nil
                shared.files[idx].etaSeconds = nil
                shared.files[idx].progressMode = .none
            }
        }
    }

    // MARK: - Progress-running ffmpeg

    private static func runWithProgress(executable ffmpeg: String,
                                        arguments args: [String],
                                        for item: MediaItem,
                                        duration: Double?,
                                        estimate: Double?) -> Bool
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
                if duration != nil {
                    shared.files[idx].progressMode = .real
                    shared.files[idx].progress = 0
                    shared.files[idx].etaSeconds = nil
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

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }

            if let range = chunk.range(of: #"time=\d{2}:\d{2}:\d{2}\.\d{2}"#, options: .regularExpression) {
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
                }
            } else {
                if duration == nil, let est = estimate, est > 0 {
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
            let ok = (task.terminationStatus == 0)
            if !ok {
                // concise failure line
                DispatchQueue.main.async {
                    AppState.shared?.log(.error, "ffmpeg failed.", fileURL: item.url, autoReveal: true)
                }
            }
            return ok
        } catch {
            print("Failed to launch ffmpeg: \(error)")
            DispatchQueue.main.async {
                AppState.shared?.log(.error, "Failed to launch ffmpeg: \(error.localizedDescription)", fileURL: item.url, autoReveal: true)
            }
            return false
        }
    }

    // MARK: - Learning hooks (speed + size)

    /// Preferred: record speed (MP/s) and size model after a success.
    private static func learnForCompleted(item: MediaItem,
                                          settings: Settings,
                                          startedAt: Date,
                                          finishedAt: Date)
    {
        guard let dur = item.meta.durationSeconds, dur > 0 else { return }
        let fps = item.meta.nominalFPS ?? 30.0

        // Compute output WxH exactly like the builder (scale → evenize).
        let (inW, inH) = inputDimensions(item.url)
        let factor: Double = {
            switch settings.scale {
            case .oneToOne: return 1.0
            case .half:     return 0.5
            case .quarter:  return 0.25
            }
        }()
        let outW = Int(ceil(Double(inW) * factor / 2.0)) * 2
        let outH = Int(ceil(Double(inH) * factor / 2.0)) * 2

        // 1) Speed sample
        let wall = finishedAt.timeIntervalSince(startedAt)
        let sample = EncodeStatsStore.makeSample(runMode: "local",
                                                 outW: outW, outH: outH,
                                                 fps: fps,
                                                 durationSec: dur,
                                                 wallTimeSec: wall,
                                                 crf: settings.qualityCRF)
        EncodeStatsStore.shared.record(sample: sample)

        // 2) Size model (bpppf @ CRF18 normalization)
        guard let out = item.finalOutputURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: out.path),
              let bytes = (attrs[.size] as? NSNumber)?.int64Value else { return }

        let totalFrames = fps * dur
        guard totalFrames > 0, outW > 0, outH > 0 else { return }

        let bpppf = (Double(bytes) * 8.0) / (Double(outW * outH) * totalFrames)
        let isHDR = inferHDR(meta: item.meta, settings: settings)

        EncodeStatsStore.shared.recordBpppf18(runMode: "local",
                                              outW: outW, outH: outH,
                                              fps: fps,
                                              crf: settings.qualityCRF,
                                              isHDR: isHDR,
                                              bpppf18: bpppf)
    }

    /// Back-compat shim: some old call sites may still call this.
    private static func learnSizeForCompleted(item: MediaItem, settings: Settings) {
        guard let dur = item.meta.durationSeconds, dur > 0 else { return }
        let fps = item.meta.nominalFPS ?? 30.0

        let (inW, inH) = inputDimensions(item.url)
        let factor: Double = {
            switch settings.scale {
            case .oneToOne: return 1.0
            case .half:     return 0.5
            case .quarter:  return 0.25
            }
        }()
        let outW = Int(ceil(Double(inW) * factor / 2.0)) * 2
        let outH = Int(ceil(Double(inH) * factor / 2.0)) * 2

        guard let out = item.finalOutputURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: out.path),
              let bytes = (attrs[.size] as? NSNumber)?.int64Value else { return }

        let totalFrames = fps * dur
        guard totalFrames > 0, outW > 0, outH > 0 else { return }

        let bpppf = (Double(bytes) * 8.0) / (Double(outW * outH) * totalFrames)
        let isHDR = inferHDR(meta: item.meta, settings: settings)

        EncodeStatsStore.shared.recordBpppf18(runMode: "local",
                                              outW: outW, outH: outH,
                                              fps: fps,
                                              crf: settings.qualityCRF,
                                              isHDR: isHDR,
                                              bpppf18: bpppf)
    }

    // MARK: - Utilities

    /// Parse "HH:MM:SS.xx" to seconds
    private static func parseHHMMSS(_ s: String) -> Double {
        let parts = s.split(separator: ":")
        guard parts.count == 3 else { return 0 }
        let h = Double(parts[0]) ?? 0
        let m = Double(parts[1]) ?? 0
        let ssec = Double(parts[2]) ?? 0
        return h*3600 + m*60 + ssec
    }

    /// Resolve ffmpeg binary
    private static func resolveFFmpegPath(_ provided: String?) -> String {
        if let p = provided, !p.isEmpty { return p }
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
            "ffmpeg"
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return "ffmpeg"
    }

    /// Input dimensions using AVFoundation
    private static func inputDimensions(_ url: URL) -> (Int, Int) {
        let asset = AVAsset(url: url)
        if let t = asset.tracks(withMediaType: .video).first {
            let s = t.naturalSize.applying(t.preferredTransform)
            return (Int(abs(s.width).rounded()), Int(abs(s.height).rounded()))
        }
        return (1920, 1080)
    }

    /// Simple HDR heuristic using *string* NCLC fields (e.g. "bt2020", "smpte2084", "arib-std-b67")
    private static func inferHDR(meta: MediaMetadata, settings: Settings) -> Bool {
        if let p = meta.colorPrimaries?.lowercased(), p.contains("2020") { return true }
        if let t = meta.transferFunction?.lowercased(),
           t.contains("2084") || t.contains("pq") || t.contains("arib-std-b67") || t.contains("hlg") {
            return true
        }
        let tag = settings.nclcTag.lowercased()
        if tag.contains("2020") || tag.contains("pq") || tag.contains("hlg") { return true }
        return false
    }
}
