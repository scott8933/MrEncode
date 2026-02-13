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
        print("MODE: Local (ffmpeg)")
        print("CRF: \(settings.qualityCRF)  Scale: \(settings.scale.rawValue)  NCLC: \(settings.nclcTag)")

        guard let ffmpeg = resolveFFmpegPath(explicitPath: ffmpegPath) else {
            print("ERROR: Could not find ffmpeg. Set path explicitly or install (e.g. /opt/homebrew/bin/ffmpeg).")
            return
        }

        // Run sequentially
        for (idx, item) in items.enumerated() {
            DispatchQueue.main.async {
                AppState.shared?.files[idx].status = .encoding
            }

            let input = item.url
            let output = OutputNamer.suggestedOutputURL(for: input, settings: settings)
            let args   = FFmpegCommandBuilder.buildArgs(input: input, output: output, settings: settings)

            print("FFMPEG → \(input.lastPathComponent)")
            let ok = runProcess(executable: URL(fileURLWithPath: ffmpeg), arguments: args)

            DispatchQueue.main.async {
                AppState.shared?.files[idx].status = ok ? .done : .error
            }
        }
    }

    // MARK: - Path resolution

    /// Resolve ffmpeg path (explicit > common Homebrew paths > PATH lookup).
    private static func resolveFFmpegPath(explicitPath: String?) -> String? {
        if let p = explicitPath, FileManager.default.isExecutableFile(atPath: p) {
            return p
        }

        // Common macOS locations
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",  // Apple Silicon Homebrew
            "/usr/local/bin/ffmpeg",     // Intel Homebrew
            "/usr/bin/ffmpeg"            // System (sometimes present)
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }

        // Fallback: PATH lookup
        if let which = try? runWhich("ffmpeg"),
           !which.isEmpty,
           FileManager.default.isExecutableFile(atPath: which) {
            return which
        }

        return nil
    }

    private static func runWhich(_ name: String) throws -> String {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = [name]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        try task.run()
        task.waitUntilExit()

        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }


    // MARK: - Process

    /// Run a process synchronously, streaming stdout/stderr. Returns true on 0 exit.
    @discardableResult
    private static func runProcess(executable: URL, arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError  = errPipe

        // Stream output line-by-line to the console
        outPipe.fileHandleForReading.readabilityHandler = { fh in
            if let s = String(data: fh.availableData, encoding: .utf8), !s.isEmpty { print(s, terminator: "") }
        }
        errPipe.fileHandleForReading.readabilityHandler = { fh in
            if let s = String(data: fh.availableData, encoding: .utf8), !s.isEmpty { fputs(s, stderr) }
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
