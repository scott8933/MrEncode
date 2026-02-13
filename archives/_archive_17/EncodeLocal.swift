import Foundation
import AVFoundation

enum EncodeLocal {

    /// Run local ffmpeg encodes sequentially.
    /// - Parameters:
    ///   - items: Media files to encode.
    ///   - settings: App settings (CRF, scale, overlays, NCLC, etc.).
    ///   - ffmpegPath: Optional explicit ffmpeg path. If nil, auto-discover.
    static func run(items: [MediaItem], settings: Settings, ffmpegPath: String? = nil) {
        print("MODE: Local (ffmpeg)")
        print("CRF: \(settings.qualityCRF)  Scale: \(settings.scale.rawValue)  NCLC: \(settings.nclcTag)")

        // Discover ffmpeg
        guard let ffmpeg = discoverFFmpeg(explicit: ffmpegPath) else {
            print("ERROR: Could not find ffmpeg. Set Preferences > ffmpeg path or install Homebrew ffmpeg.")
            DispatchQueue.main.async {
                if let shared = AppState.shared {
                    for i in items {
                        if let idx = shared.files.firstIndex(where: { $0.id == i.id }) {
                            shared.files[idx].status = .error
                            shared.files[idx].statusReason = "ffmpeg not found"
                        }
                    }
                }
            }
            return
        }

        // Process items one-by-one
        for item in items {
            // Skip blocked or already done
            if case .blocked = item.status { continue }
            if case .done = item.status { continue }

            // Flip to "encoding…" in UI and clear old timing
            DispatchQueue.main.async {
                if let shared = AppState.shared,
                   let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                    shared.files[idx].status = .encoding
                    shared.files[idx].statusReason = nil
                    shared.files[idx].actualEncodeSeconds = nil   // <-- clear prior actual time
                }
            }

            // Choose output path:
            //  - If this item was re-queued, reuse its previous final path to OVERWRITE.
            //  - Otherwise, use the standard suggested output name.
            let outputURL: URL = {
                // Prefer the value carried on the item itself
                if let prev = item.finalOutputURL {
                    return prev
                }
                // Or ask the shared store (in case callers passed a stale copy)
                if let shared = AppState.shared,
                   let idx = shared.files.firstIndex(where: { $0.id == item.id }),
                   let prev = shared.files[idx].finalOutputURL {
                    return prev
                }
                // First time render → normal suggested name
                return OutputNamer.suggestedOutputURL(for: item.url, settings: settings)
            }()

            // Build ffmpeg args (-y is already included by your builder to allow overwrite)
            let args = FFmpegCommandBuilder.buildArgs(item: item, output: outputURL, settings: settings)

            // Debug print
            print("FFMPEG ARGS:")
            print(args.joined(separator: " "))

            // Launch
            let startedAt = Date()
            let ok = runProcess(executable: ffmpeg, arguments: args)
            let finishedAt = Date()

            // Update UI + learning hooks
            DispatchQueue.main.async {
                guard let shared = AppState.shared,
                      let idx = shared.files.firstIndex(where: { $0.id == item.id }) else { return }

                if ok {
                    // Mark the actual written path (fixes “-2/_2” confusion and enables overwrite on re-queue)
                    shared.files[idx].finalOutputURL = outputURL
                    shared.files[idx].status = .done
                    shared.files[idx].statusReason = nil

                    // Store real wall-clock encode time for the row
                    shared.files[idx].actualEncodeSeconds = finishedAt.timeIntervalSince(startedAt)

                    // (optional) time-learning for Local estimator
                    EncodeTimeEstimator.recordCompleted(
                        url: item.url,
                        meta: shared.files[idx].meta,
                        settings: shared.settings,
                        runMode: .localFFmpeg,
                        startedAt: startedAt,
                        finishedAt: finishedAt
                    )

                    // (optional) size-learning for Local estimator
                    learnSizeForCompleted(item: shared.files[idx], settings: shared.settings)

                } else {
                    shared.files[idx].status = .error
                    shared.files[idx].statusReason = "ffmpeg failed"
                }
            }
        }

    }

    // Learn bpppf@18 from the finished output file and record into stats.
    private static func learnSizeForCompleted(item: MediaItem, settings: Settings) {
        guard let final = item.finalOutputURL else { return }
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: final.path),
              let fileBytes = (attrs[.size] as? NSNumber)?.int64Value else { return }

        let asset = AVAsset(url: item.url)
        guard let vTrack = asset.tracks(withMediaType: .video).first else { return }

        // Geometry/time must reflect the *output* geometry (based on UI scale)
        let src = vTrack.naturalSize.applying(vTrack.preferredTransform)
        let srcW = Int(abs(src.width).rounded())
        let srcH = Int(abs(src.height).rounded())
        guard srcW > 0, srcH > 0 else { return }

        let scale = settings.scale.factor
        let outW = max(1, Int(round(Double(srcW) * scale)))
        let outH = max(1, Int(round(Double(srcH) * scale)))

        let fps = item.meta.nominalFPS ?? (vTrack.nominalFrameRate > 0 ? Double(vTrack.nominalFrameRate) : 30.0)
        let secs = item.meta.durationSeconds ?? CMTimeGetSeconds(asset.duration)
        guard secs.isFinite, secs > 0 else { return }

        // If there is audio, subtract its rough size (assumes 128k AAC like the builder)
        let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty
        let audio_bps = hasAudio ? 128_000.0 : 0.0
        let audioBytes = Int64((audio_bps * secs) / 8.0)

        // Approx video-only bytes
        let videoBytes = max(0, fileBytes - audioBytes)
        let videoBits = Double(videoBytes) * 8.0

        // Raw bpppf at the current CRF
        let denom = Double(outW * outH) * fps * secs
        guard denom > 0 else { return }
        let bpppf = videoBits / denom

        // Normalize to CRF18 so we can reuse across CRFs
        let crf = settings.qualityCRF
        let crfFactor = pow(2.0, (18.0 - Double(crf)) / 6.0) // lower CRF -> higher factor
        let bpppf18 = bpppf / crfFactor

        // HDR flag from transfer function
        let tf = (item.meta.transferFunction ?? "").lowercased()
        let isHDR = tf.contains("2084") || tf.contains("pq") || tf.contains("hlg") || tf.contains("2100")

        EncodeStatsStore.shared.recordBpppf18(
            runMode: "local",
            outW: outW, outH: outH,
            fps: fps,
            crf: crf,
            isHDR: isHDR,
            bpppf18: bpppf18
        )
    }

    // MARK: - ffmpeg discovery

    private static func discoverFFmpeg(explicit: String?) -> URL? {
        // 1) Explicit path (Preferences)
        if let p = explicit, !p.isEmpty {
            let u = URL(fileURLWithPath: p)
            if FileManager.default.isExecutableFile(atPath: u.path) { return u }
        }
        // 2) Common Homebrew installs
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",   // Apple Silicon brew
            "/usr/local/bin/ffmpeg",      // Intel brew
            "/usr/bin/ffmpeg"             // System (rare)
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        // 3) PATH via /usr/bin/env
        if let which = whichCmd("ffmpeg") { return which }
        return nil
    }

    private static func whichCmd(_ name: String) -> URL? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["which", name]

        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let s = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !s.isEmpty,
                   FileManager.default.isExecutableFile(atPath: s) {
                    return URL(fileURLWithPath: s)
                }
            }
        } catch { }
        return nil
    }

    // MARK: - Process runner

    /// Returns true if ffmpeg exited with status 0.
    private static func runProcess(executable: URL, arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError  = errPipe

        // Stream output to console
        outPipe.fileHandleForReading.readabilityHandler = { fh in
            if let s = String(data: fh.availableData, encoding: .utf8), !s.isEmpty {
                print(s, terminator: "")
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { fh in
            if let s = String(data: fh.availableData, encoding: .utf8), !s.isEmpty {
                fputs(s, stderr)
            }
        }

        do {
            defer {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
            }
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            print("Failed to launch ffmpeg: \(error)")
            return false
        }
    }
}
