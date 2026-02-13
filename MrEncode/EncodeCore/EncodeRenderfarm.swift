//
//  EncodeRenderfarm.swift
//  MrEncode
//
//  Remote encoding via Thinkbox Deadline.
//  Submits Shell plugin jobs that invoke the MrEncode CLI binary — the same
//  way a droplet does.  The farm node runs EncodeCore through EncodeCLI,
//  so the quality curve is identical to local encodes.
//

import Foundation

enum EncodeRenderfarm {

    // MARK: - Public entry point

    /// Submit a batch of items to Deadline (one Shell job per item).

#if !MR_ENCODE_CLI
    static func run(items: [MediaItem], settings: Settings) {
        let deadlineCmd = settings.deadlineCommandPath.isEmpty
            ? (detectDeadlineCommand() ?? "/Applications/Thinkbox/Deadline10/Resources/deadlinecommand")
            : settings.deadlineCommandPath

        // Immediate UI feedback: mark all items as submitting
        DispatchQueue.main.async {
            for item in items {
                AppCore.shared.updateFile(id: item.id) { file in
                    guard file.status != .blocked else { return }
                    file.status       = .encoding
                    file.statusReason = "Submitting to Deadline…"
                    file.progressMode = .fake
                    file.progress     = nil
                    file.etaSeconds   = nil
                }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for item in items {
                // Cancel / pause gates (same pattern as local path)
                if EncodingService.shared.wasGloballyCancelled {
                    print("🛑 Global cancel detected - stopping Deadline submissions")
                    break
                }
                while EncodingService.shared.isGloballyPaused {
                    if EncodingService.shared.wasGloballyCancelled { break }
                    Thread.sleep(forTimeInterval: 0.5)
                }

                // Farm path sanity check — input must be on a shared volume
                if case .failure(let error) = isInputPathAcceptableForFarm(item.url) {
                    DispatchQueue.main.async {
                        AppCore.shared.updateFile(id: item.id) { file in
                            file.status       = .blocked
                            file.statusReason = error.message
                            file.progressMode = .none
                            file.progress     = nil
                            file.etaSeconds   = nil
                        }
                        AppState.shared?.pushMessage(
                            level: .warning, error.message,
                            filename: item.url.lastPathComponent,
                            code: .farmPath, originKey: "farm-path")
                    }
                    continue
                }

                // Resolve output URL the same way the local path does
                let output = item.plannedOutputURL
                    ?? OutputNamer.suggestedOutputURL(for: item.url, settings: settings)

                // Write a temporary preset file containing the current settings.
                // The CLI binary reads this the same way a droplet does.
                let presetURL: URL
                do {
                    presetURL = try writePresetFile(settings: settings)
                } catch {
                    reportFailure(itemID: item.id, exitCode: -1,
                                  output: "Failed to write preset file: \(error)")
                    continue
                }

                // Submit
                let result = submitShellJob(
                    deadlineCmd: deadlineCmd,
                    presetURL:   presetURL,
                    input:       item.url,
                    output:      output,
                    settings:    settings)

                // Clean up the temp preset
                try? FileManager.default.removeItem(at: presetURL)

                // Report result back to UI
                DispatchQueue.main.async {
                    AppCore.shared.updateFile(id: item.id) { file in
                        file.progressMode = .none
                        file.progress     = nil
                        file.etaSeconds   = nil

                        if result.exitCode == 0 {
                            file.finalOutputURL = result.output
                            file.status         = .queued
                            file.statusReason   = "Submitted to Deadline."
                            file.isChecked      = false
                        } else {
                            let msg = result.rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                            file.status       = .error
                            file.statusReason = msg.isEmpty
                                ? "Deadline submit failed (code \(result.exitCode))."
                                : msg
                        }
                    }

                    let jobID  = extractDeadlineJobID(from: result.rawOutput)
                    let detail = result.exitCode == 0
                        ? buildSuccessDetail(jobID: jobID, output: result.rawOutput)
                        : buildErrorDetail(exitCode: result.exitCode, output: result.rawOutput)

                    if result.exitCode == 0 {
                        let summary = jobID.map { "Remote submit successful – Job \($0)" }
                            ?? "Remote submit successful"
                        AppState.shared?.pushMessage(
                            level: .info, summary,
                            filename: item.url.lastPathComponent,
                            code: .other, originKey: "deadline-submit",
                            detail: detail, jobID: jobID)
                    } else {
                        AppState.shared?.pushMessage(
                            level: .error, "Remote submit failed – check status",
                            filename: item.url.lastPathComponent,
                            code: .other, originKey: "deadline-submit",
                            detail: detail)
                    }
                }

                // Throttle submissions slightly
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
#endif

    
    
    // MARK: - Types

    struct SubmissionResult {
        let input:     URL
        let output:    URL
        let exitCode:  Int32
        let rawOutput: String
        let jobID:     String?
    }

    struct Lists {
        var pools:  [String]
        var groups: [String]
    }

    // MARK: - Preset file (shared with droplet path)

    /// Serialise current settings into a temporary .mrepreset preset file.
    /// The CLI binary reads this identically to a droplet-exported preset.
    /// Serialise current settings into a temporary droplet preset JSON file.
    private static func writePresetFile(settings: Settings) throws -> URL {
        let droplet = DropletFile(presetName: "deadline-job", settings: settings)
        let data    = try JSONEncoder().encode(droplet)

        let tmpDir  = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url     = tmpDir.appendingPathComponent("MrEncode_deadline_\(UUID().uuidString).mrepreset")
        try data.write(to: url)
        return url
    }

    // MARK: - Shell job submission

    /// Build and submit a Deadline Shell plugin job that invokes MrEncode CLI.
    /// The command the farm node runs is exactly:
    ///   /path/to/MrEncode.app/Contents/MacOS/MrEncode --cli --preset-file <preset> <input>
    /// Internal (not private) so DropletRunner can call it for single-item CLI submission.
    /// todo: need to update that comment above, there is no DropletRunner as such right now
    static func submitShellJob(deadlineCmd: String,
                                       presetURL:   URL,
                                       input:       URL,
                                       output:      URL,
                                       settings:    Settings) -> SubmissionResult {
        let fm = FileManager.default

        // The preset file needs to live on a shared path the farm can read.
        // Copy it next to the input file (which already passed the shared-path check).
        let sharedPreset = input.deletingLastPathComponent()
            .appendingPathComponent(".mrencode_preset_\(UUID().uuidString).mrepreset")

        do {
            try fm.copyItem(at: presetURL, to: sharedPreset)
        } catch {
            return SubmissionResult(input: input, output: output,
                                    exitCode: -1,
                                    rawOutput: "Failed to copy preset to shared path: \(error)",
                                    jobID: nil)
        }

        defer { try? fm.removeItem(at: sharedPreset) }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("MrEncode_\(UUID().uuidString)", isDirectory: true)

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

            let jobInfoURL    = tmpDir.appendingPathComponent("jobInfo.job")
            let pluginInfoURL = tmpDir.appendingPathComponent("pluginInfo.job")

            try writeJobInfo(to: jobInfoURL, output: output, settings: settings)
            try writePluginInfo(to: pluginInfoURL,
                                presetURL: sharedPreset,
                                input:     input)

            let (code, out) = runCLI(path: deadlineCmd,
                                     args: ["-SubmitJob", jobInfoURL.path, pluginInfoURL.path])

            try? fm.removeItem(at: tmpDir)
            return SubmissionResult(input: input, output: output,
                                    exitCode: code, rawOutput: out,
                                    jobID: code == 0 ? extractDeadlineJobID(from: out) : nil)
        } catch {
            try? fm.removeItem(at: tmpDir)
            return SubmissionResult(input: input, output: output,
                                    exitCode: -1,
                                    rawOutput: "Failed to write/submit job: \(error)",
                                    jobID: nil)
        }
    }

    // MARK: - Job file writers

    /// jobInfo.job — Deadline job metadata.  Uses Shell plugin (not FFmpeg).
    private static func writeJobInfo(to url: URL, output: URL, settings: Settings) throws {
        let name = settings.jobName.isEmpty
            ? output.deletingPathExtension().lastPathComponent
            : settings.jobName

        var lines: [String] = [
            "Name=\(escape(name))",
            "Plugin=Shell",
            "Frames=0",
            "ChunkSize=1",
            "Priority=\(settings.priority)",
            "OutputDirectory0=\(output.deletingLastPathComponent().path)",
            "OutputFilename0=\(output.lastPathComponent)"
        ]

        if !settings.batchName.isEmpty   { lines.append("BatchName=\(escape(settings.batchName))") }
        if !settings.comment.isEmpty     { lines.append("Comment=\(escape(settings.comment))") }
        if !settings.pool.isEmpty        { lines.append("Pool=\(escape(settings.pool))") }
        if !settings.secondaryPool.isEmpty { lines.append("SecondaryPool=\(escape(settings.secondaryPool))") }
        if !settings.group.isEmpty       { lines.append("Group=\(escape(settings.group))") }

        try lines.joined(separator: "\n").appending("\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    /// pluginInfo.job — Shell plugin: the command and args the farm node executes.
    /// Layout matches Deadline's Shell plugin expectations.
    private static func writePluginInfo(to url: URL,
                                        presetURL: URL,
                                        input:     URL) throws {
        // The executable path on the farm.  Assumes the app is installed in the
        // same location as on the submitting machine.  This is the standard
        // assumption for macOS render farms.
        let executablePath = CommandLine.arguments[0]  // path to the running MrEncode binary

        let command = [
            executablePath,
            "--cli",
            "--droplet", presetURL.path,
            input.path
        ].map { "\"\($0)\"" }.joined(separator: " ")

        let lines: [String] = [
            "Command=\(command)",
            "WorkDirectory=",
            "ShowWindow=0"
        ]

        try lines.joined(separator: "\n").appending("\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Deadline detection & CLI

    /// Locate `deadlinecommand` via the shared marker file, or return nil.
    static func detectDeadlineCommand() -> String? {
        let marker = "/Users/Shared/Thinkbox/DEADLINE_PATH"
        guard let s = try? String(contentsOfFile: marker, encoding: .utf8) else { return nil }
        let dir = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dir.isEmpty else { return nil }

        let res = (dir as NSString).appendingPathComponent("deadlinecommand")
        if FileManager.default.isExecutableFile(atPath: res) { return res }

        let bin = (dir as NSString).appendingPathComponent("bin/deadlinecommand")
        if FileManager.default.isExecutableFile(atPath: bin) { return bin }

        return nil
    }

    /// Fetch pool and group lists from Deadline (used by the settings UI).
    static func fetchLists(deadlineCmd: String) throws -> Lists {
        let pools  = try runAndCollect(deadlineCmd, ["-GetPoolNames"])
        let groups = try runAndCollect(deadlineCmd, ["-GetGroupNames"])
        return Lists(pools: pools, groups: groups)
    }

    // MARK: - Path sanity

    /// Reject paths that farm nodes won't be able to reach.
    static func isInputPathAcceptableForFarm(_ url: URL) -> Result<Void, DropletError> {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let forbidden = [home + "/Desktop", home + "/Downloads"]

        if forbidden.contains(where: { path.hasPrefix($0 + "/") || path == $0 }) {
            return .failure(.validation(
                message: "Path is under Desktop or Downloads; farm nodes won't see this."))
        }
        if path.hasPrefix(home + "/") && !path.hasPrefix("/Volumes/") {
            return .failure(.validation(
                message: "Path is under your local home folder. Use a shared path (e.g. /Volumes/Share/…)."))
        }
        return .success(())
    }

    
    
    // MARK: - Private helpers
    
#if !MR_ENCODE_CLI
    private static func reportFailure(itemID: UUID, exitCode: Int32, output: String) {
        DispatchQueue.main.async {
            AppCore.shared.updateFile(id: itemID) { file in
                file.status       = .error
                file.statusReason = output
                file.progressMode = .none
                file.progress     = nil
                file.etaSeconds   = nil
            }
        }
    }
#endif
    

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func runCLI(path: String, args: [String]) -> (Int32, String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments     = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = pipe
        do { try task.run() } catch { return (-1, "Failed to launch \(path): \(error)") }
        task.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (task.terminationStatus, out)
    }

    private static func runAndCollect(_ cmd: String, _ args: [String]) throws -> [String] {
        let (code, out) = runCLI(path: cmd, args: args)
        guard code == 0 else {
            throw NSError(domain: "Deadline", code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey: out])
        }
        return out.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Detail builders

    private static let detailDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    private static func buildSuccessDetail(jobID: String?, output: String) -> String {
        var lines = ["=== Deadline Submission Success ==="]
        if let jid = jobID, !jid.isEmpty { lines.append("Job ID: \(jid)") }
        lines.append("Timestamp: \(detailDateFormatter.string(from: Date()))")
        lines.append("")
        lines.append("=== Deadline Output ===")
        lines.append(output.trimmingCharacters(in: .whitespacesAndNewlines))
        return lines.joined(separator: "\n")
    }

    private static func buildErrorDetail(exitCode: Int32, output: String) -> String {
        var lines = ["=== Deadline Submission Failed ==="]
        lines.append("Exit Code: \(exitCode)")
        lines.append("Timestamp: \(detailDateFormatter.string(from: Date()))")
        lines.append("")
        lines.append("=== Deadline Output ===")
        lines.append(output.trimmingCharacters(in: .whitespacesAndNewlines))
        return lines.joined(separator: "\n")
    }

    private static func extractDeadlineJobID(from s: String) -> String? {
        // "Job submitted successfully: Name [62c7d1f9e44adf2b3f35e0c7]"
        if let m = s.range(of: #"\[([0-9a-f]{24})\]"#, options: .regularExpression) {
            return String(s[m]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        if let m = s.range(of: #"[0-9a-f]{24}"#, options: .regularExpression) {
            return String(s[m])
        }
        return nil
    }
}
