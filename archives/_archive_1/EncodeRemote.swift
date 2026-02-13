import Foundation

enum DeadlineService {

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

    // MARK: - CLI

    /// Bare-bones CLI runner. Returns (exit, stdout+stderr).
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

    // MARK: - Detection & Lists

    /// Try the classic marker file used by Deadline installers.
    static func detectFromMarker() -> String? {
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

    /// Fetch Pools and Groups with two calls. Throws a readable error if either fails.
    static func fetchLists(deadlineCmd: String) throws -> Lists {
        let (pCode, pOut) = runCLI(path: deadlineCmd, args: ["-GetPoolNames"])
        guard pCode == 0 else { throw NSError(domain: "Deadline", code: Int(pCode), userInfo: [NSLocalizedDescriptionKey: pOut]) }

        let (gCode, gOut) = runCLI(path: deadlineCmd, args: ["-GetGroupNames"])
        guard gCode == 0 else { throw NSError(domain: "Deadline", code: Int(gCode), userInfo: [NSLocalizedDescriptionKey: gOut]) }

        let pools  = pOut.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let groups = gOut.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        return Lists(pools: pools, groups: groups)
    }

    // MARK: - Submissions

    /// Submit one ffmpeg job per input using Deadline's CommandLine plugin.
    /// - Parameters:
    ///   - deadlineCmd: full path to `deadlinecommand`
    ///   - items: inputs to encode
    ///   - settings: UI settings (CRF, scale, NCLC, pools, etc.)
    ///   - ffmpegPath: path to ffmpeg on the farm nodes (what the workers can resolve)
    ///                 e.g. "/usr/local/bin/ffmpeg" or a shared path in your environment.
    /// - Returns: A result per submitted item (exit code + raw output).
    @discardableResult
    static func submitFFmpegJobs(deadlineCmd: String,
                                 items: [MediaItem],
                                 settings: Settings,
                                 ffmpegPath: String) -> [SubmissionResult] {

        var results: [SubmissionResult] = []
        let fm = FileManager.default

        for item in items {
            let input = item.url
            // Note: for farm execution, you may want to map paths to a network share.
            let output = suggestedOutputURLBesideInput(input)

            // Build ffmpeg argv with our shared builder (CRF, scale, NCLC)
            let ffArgs = FFmpegCommandBuilder.buildArgs(input: input, output: output, settings: settings)

            // Create temp files for job info + plugin info
            let tmpDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("MrHEVC_\(UUID().uuidString)")
            let tmpURL = URL(fileURLWithPath: tmpDir)
            try? fm.createDirectory(at: tmpURL, withIntermediateDirectories: true)

            let jobInfoURL   = tmpURL.appendingPathComponent("job_info.ini")
            let pluginInfoURL = tmpURL.appendingPathComponent("plugin_info.ini")

            do {
                try writeJobInfo(to: jobInfoURL, input: input, output: output, settings: settings)
                try writePluginInfo(to: pluginInfoURL, ffmpegPath: ffmpegPath, ffmpegArgs: ffArgs)

            } catch {
                let msg = "Failed to write job/plugin info: \(error)"
                results.append(.init(input: input, output: output, exitCode: -1, rawOutput: msg))
                continue
            }

            // Submit: -SubmitJob <jobInfo> <pluginInfo>
            let (code, out) = runCLI(path: deadlineCmd, args: ["-SubmitJob", jobInfoURL.path, pluginInfoURL.path])
            results.append(.init(input: input, output: output, exitCode: code, rawOutput: out))

            // Clean up temp files
            try? fm.removeItem(at: tmpURL)
        }

        return results
    }

    // MARK: - File writers

    /// Minimal but useful Job Info for CommandLine plugin.
    private static func writeJobInfo(to url: URL, input: URL, output: URL, settings: Settings) throws {
        var lines: [String] = []

        // Name
        let userName = settings.jobName.isEmpty
            ? input.deletingPathExtension().lastPathComponent + " → HEVC"
            : settings.jobName
        lines.append("Name=\(escape(userName))")

        // Optional batch name
        if !settings.batchName.isEmpty {
            lines.append("BatchName=\(escape(settings.batchName))")
        }

        // Comment
        if !settings.comment.isEmpty {
            lines.append("Comment=\(escape(settings.comment))")
        }

        // Pools / Group
        if !settings.pool.isEmpty          { lines.append("Pool=\(escape(settings.pool))") }
        if !settings.secondaryPool.isEmpty { lines.append("SecondaryPool=\(escape(settings.secondaryPool))") }
        if !settings.group.isEmpty         { lines.append("Group=\(escape(settings.group))") }

        // Priority (0–100, Deadline allows 0–100)
        lines.append("Priority=\(settings.priority)")

        // Single task job (command-line). Frames are optional; many keep 0 or 1.
        lines.append("Frames=0")
        lines.append("ChunkSize=1")

        // Dependencies: comma or whitespace separated Job IDs
        let deps = settings.dependencies
            .split(whereSeparator: { ", \n\t".contains($0) })
            .map { String($0) }
            .filter { !$0.isEmpty }
        if !deps.isEmpty {
            lines.append("JobDependencies=\(deps.joined(separator: ","))")
        }

        // Optional: machine limits, etc., can go here later.

        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Plugin Info for the CommandLine plugin: executable + arguments.
    private static func writePluginInfo(to url: URL, ffmpegPath: String, ffmpegArgs: [String]) throws {
        // CommandLine plugin usually expects:
        // Executable=<path to binary>
        // Arguments=<single string of args>
        // (Other keys like Shell/StartupDirectory can be added if you need.)
        let argString = ffmpegArgs.map { shellEscape($0) }.joined(separator: " ")
        var lines: [String] = []
        lines.append("Executable=\(ffmpegPath)")
        lines.append("Arguments=\(argString)")
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Utilities

    /// Put output next to input with `_hevc.mp4`, avoiding collisions.
    private static func suggestedOutputURLBesideInput(_ input: URL) -> URL {
        let folder = input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let ext = "mp4"
        var out = folder.appendingPathComponent("\(stem)_hevc").appendingPathExtension(ext)

        var idx = 2
        let fm = FileManager.default
        while fm.fileExists(atPath: out.path) {
            out = folder.appendingPathComponent("\(stem)_hevc_\(idx)").appendingPathExtension(ext)
            idx += 1
        }
        return out
    }

    /// Escape simple INI values (very conservative).
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Shell-escape for Arguments line (so spaces/quotes survive).
    private static func shellEscape(_ s: String) -> String {
        // Wrap in single quotes and escape existing single quotes:  ' -> '\''
        if s.isEmpty { return "''" }
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
