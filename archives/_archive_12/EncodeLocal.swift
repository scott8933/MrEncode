// =============================
// File: EncodeLocal.swift
// =============================
import Foundation

enum EncodeLocal {

    /// Run local ffmpeg encodes sequentially.
    /// - Parameters:
    ///   - items: Media files to encode.
    ///   - settings: App settings (CRF, scale, NCLC, etc.).
    ///   - ffmpegPath: Optional explicit ffmpeg path. If nil, auto-discover.
    static func run(items: [MediaItem], settings: Settings, ffmpegPath: String? = nil) {
        print("▶️ EncodeLocal.run items:", items.count)
        print("MODE: Local (ffmpeg)")
        print("CRF: \(settings.qualityCRF)  Scale: \(settings.scale.rawValue)  NCLC: \(settings.nclcTag)")

        // Resolve ffmpeg binary
        guard let ffmpeg = resolveFFmpegPath(explicitPath: ffmpegPath) else {
            print("ERROR: ffmpeg not found. Specify a path in Preferences or install via Homebrew.")
            return
        }

        // Process files one-by-one
        for item in items {

            // Set UI state -> encoding (find by id; index order may differ)
            DispatchQueue.main.async {
                if let shared = AppState.shared,
                   let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                    shared.files[idx].status = .encoding
                    shared.files[idx].statusReason = nil
                }
            }

            // Build output path and ensure the folder exists
            let outputURL = OutputNamer.suggestedOutputURL(for: item.url, settings: settings)
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
                       let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                        shared.files[idx].status = .error
                        shared.files[idx].statusReason = "Could not create output directory."
                    }
                }
                continue
            }

            // === Build with freshest metadata (coalesce from AppState; fallback to sync extract) ===
            var currentItem = item

            if let shared = AppState.shared,
               let live = shared.files.first(where: { $0.url == item.url }) {
                currentItem.meta = live.meta
            }

            if currentItem.meta.startTimecode == nil || currentItem.meta.nominalFPS == nil {
                let fresh = MetadataExtractor.extract(for: currentItem.url)
                if currentItem.meta.startTimecode == nil { currentItem.meta.startTimecode = fresh.startTimecode }
                if currentItem.meta.nominalFPS == nil   { currentItem.meta.nominalFPS   = fresh.nominalFPS }
                if currentItem.meta.colorPrimaries == nil   { currentItem.meta.colorPrimaries   = fresh.colorPrimaries }
                if currentItem.meta.transferFunction == nil { currentItem.meta.transferFunction = fresh.transferFunction }
                if currentItem.meta.ycbcrMatrix == nil      { currentItem.meta.ycbcrMatrix      = fresh.ycbcrMatrix }

                // Push improvements back to UI model so the table reflects them
                if let shared = AppState.shared,
                   let i = shared.files.firstIndex(where: { $0.url == currentItem.url }) {
                    DispatchQueue.main.async {
                        shared.files[i].meta = currentItem.meta
                    }
                }
            }

            // Compose full args
            let args = FFmpegCommandBuilder.buildArgs(item: currentItem, output: outputURL, settings: settings)

            // Debug breadcrumb for timecode path
            if settings.burnInTimecode {
                if let tc = currentItem.meta.startTimecode, let fps = currentItem.meta.nominalFPS {
                    print("Overlay[TC]: \(item.url.lastPathComponent) start=\(tc) fps=\(fps)")
                } else {
                    print("Overlay[PTS]: \(item.url.lastPathComponent) (missing TC or FPS)")
                }
            }

            // Show command (trim for readability)
            if let iPos = args.firstIndex(of: "-i"), iPos + 1 < args.count {
                let inPath = args[iPos + 1]
                let outPath = outputURL.path
                print("FFMPEG ARGS:")
                print(args.joined(separator: " ")
                    .replacingOccurrences(of: inPath, with: URL(fileURLWithPath: inPath).lastPathComponent)
                    .replacingOccurrences(of: outPath, with: URL(fileURLWithPath: outPath).lastPathComponent))
            }
            
            // Start the timer:
            let startedAt = Date()

            // Run ffmpeg
            let ok = runProcess(executable: URL(fileURLWithPath: ffmpeg), arguments: args)
            
            // End the timer:
            let finishedAt = Date()

            // Update UI status — record the actual output path on success
            DispatchQueue.main.async {
                guard let shared = AppState.shared else { return }
                if ok {
                    shared.markFinished(itemID: item.id, outputURL: outputURL)
                } else if let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                    shared.files[idx].status = .error
                    shared.files[idx].statusReason = "ffmpeg failed"
                }
            }
        }
    }

    // MARK: - Path resolution

    /// Resolve ffmpeg path (explicit > common Homebrew paths > PATH lookup).
    private static func resolveFFmpegPath(explicitPath: String?) -> String? {
        if let p = explicitPath, FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",  // Apple Silicon Homebrew
            "/usr/local/bin/ffmpeg",     // Intel Homebrew
            "/usr/bin/ffmpeg",           // System (rare)
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        // Fallback to PATH lookup
        let which = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in which.split(separator: ":") {
            let p = "\(dir)/ffmpeg"
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        return nil
    }

    // MARK: - Process launcher

    /// Launches ffmpeg and streams stdout/stderr to the console.
    /// - Returns: true if exit status == 0
    private static func runProcess(executable: URL, arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError  = errPipe

        // Stream output
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            if let s = String(data: handle.availableData, encoding: .utf8), !s.isEmpty {
                print(s, terminator: "")
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            if let s = String(data: handle.availableData, encoding: .utf8), !s.isEmpty {
                print(s, terminator: "")
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
