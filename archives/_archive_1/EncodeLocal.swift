// =============================
// File: Encoder.swift
// =============================
import Foundation

enum Encoder {

    // MARK: - Public API

    /// Remote path — thin for now; you likely call into DeadlineService here.
    static func submitToDeadline(items: [MediaItem], settings: Settings) {
        // Placeholder: print command plan (same as you had)
        print("MODE: Deadline")
        print("Priority: \(settings.priority) Pool: \(settings.pool) Secondary: \(settings.secondaryPool) Group: \(settings.group)")
        print("JobName: \(settings.jobName) Comment: \(settings.comment) Deps: \(settings.dependencies)")
        print("BatchName: \(settings.batchName)")
        print("Quality (CRF): \(settings.qualityCRF) Scale: \(settings.scale.rawValue) NCLC: \(settings.nclcTag)")

        for i in items {
            let outURL = suggestedOutputURL(for: i.url)
            let args = FFmpegCommandBuilder.buildArgs(input: i.url, output: outURL, settings: settings)
            print("DEADLINE ARGS → \(args.joined(separator: " "))")
        }

        // Later:
        // DeadlineService.submit(items: items, settings: settings)
        //   where you serialize args into .job/.plugin and run `deadlinecommand`
    }

    /// Local encoding via ffmpeg.
    /// - Parameters:
    ///   - items: media files to encode
    ///   - settings: app settings (CRF, scale, NCLC, etc.)
    ///   - ffmpegPath: optional explicit ffmpeg path; if nil we auto-discover
    static func encodeLocally(items: [MediaItem], settings: Settings, ffmpegPath: String? = nil) {
        print("MODE: Local ffmpeg")
        print("Quality (CRF): \(settings.qualityCRF) Scale: \(settings.scale.rawValue) NCLC: \(settings.nclcTag)")

        guard let ffmpeg = resolveFFmpegPath(explicitPath: ffmpegPath) else {
            print("ERROR: Could not find ffmpeg. Set path or install via Homebrew (e.g. /opt/homebrew/bin/ffmpeg).")
            return
        }

        for item in items {
            let input = item.url
            let output = suggestedOutputURL(for: input)
            let args = FFmpegCommandBuilder.buildArgs(input: input, output: output, settings: settings)
            print("FFMPEG → \(input.path)")
            let ok = runProcess(executable: URL(fileURLWithPath: ffmpeg), arguments: args)
            if ok {
                print("✓ Encoded: \(output.path)")
            } else {
                print("✗ Failed: \(input.lastPathComponent)")
            }
        }
    }

    // MARK: - Helpers

    /// Try to resolve ffmpeg path (explicit > common Homebrew paths > /usr/local/bin > PATH).
    private static func resolveFFmpegPath(explicitPath: String?) -> String? {
        if let p = explicitPath, FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",   // Apple Silicon Homebrew default
            "/usr/local/bin/ffmpeg",      // Intel Homebrew default
            "/usr/bin/ffmpeg"             // sometimes present
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        // Fallback: try `which ffmpeg`
        if let which = try? runWhich("ffmpeg"), !which.isEmpty, FileManager.default.isExecutableFile(atPath: which) {
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
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Create an output path next to the input: `name_hevc.mp4` (keeps extension .mp4).
    private static func suggestedOutputURL(for input: URL) -> URL {
        let folder = input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let ext = "mp4" // standard container for hvc1-tagged HEVC
        var out = folder.appendingPathComponent("\(stem)_hevc").appendingPathExtension(ext)

        // If a file exists, add a numeric suffix
        var idx = 2
        let fm = FileManager.default
        while fm.fileExists(atPath: out.path) {
            out = folder.appendingPathComponent("\(stem)_hevc_\(idx)").appendingPathExtension(ext)
            idx += 1
        }
        return out
    }

    /// Run a process synchronously, streaming stdout/stderr to the console. Returns success.
    @discardableResult
    private static func runProcess(executable: URL, arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError  = errPipe

        // Stream output to console line-by-line
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                print(line, terminator: "")
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            if let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty {
                fputs(line, stderr)
            }
        }

        do {
            // Always run this cleanup when we exit this scope
            defer {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
            }

            try task.run()
            task.waitUntilExit()
        } catch {
            print("Failed to launch ffmpeg: \(error)")
            return false
        }

        return task.terminationStatus == 0
    }
}
