//
//  CLIProgressPrinter.swift
//  MrEncode
//
//  Created by scott ulrich on 2/2/26.
//


import Foundation

final class CLIProgressPrinter {

    enum Mode {
        case human
        case json
        case none
    }

    private let mode: Mode
    private let fileHandle: FileHandle?
    private var lastHumanLineLen: Int = 0

    // Throttle disk flushes for JSONL file writing
    private var lastFlushWall: TimeInterval = 0
    private let flushEverySeconds: TimeInterval = 0.5

    // Runtime debug gate (off by default)
    private var debugEnabled: Bool {
        ProcessInfo.processInfo.environment["MR_ENCODE_DEBUG_PROGRESS"] == "1"
    }

    private func dlog(_ msg: String) {
        guard debugEnabled else { return }
        // Avoid NSLog here since it goes to unified logging; keep it on stderr.
        FileHandle.standardError.write(("[MrEncode][Progress] \(msg)\n").data(using: .utf8)!)
    }

    init(mode: Mode, progressFileURL: URL?) {
        self.mode = mode

        if let url = progressFileURL {
            // Ensure parent directory exists (AppleScript may do this, but CLI should be robust).
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                if ProcessInfo.processInfo.environment["MR_ENCODE_DEBUG_PROGRESS"] == "1" {
                    FileHandle.standardError.write(
                        "[MrEncode][Progress] Failed to create progress directory: \(error)\n"
                            .data(using: .utf8)!
                    )
                }
            }

            // Create the file if needed; open for writing.
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)

            do {
                let fh = try FileHandle(forWritingTo: url)
                try fh.seekToEnd()
                self.fileHandle = fh
                dlog("Progress file enabled: \(url.path)")
            } catch {
                self.fileHandle = nil
                dlog("Failed to open progress file for writing: \(error)")
            }
        } else {
            self.fileHandle = nil
        }

        self.lastFlushWall = Date().timeIntervalSince1970
    }

    deinit {
        // Best-effort final flush/close
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
    }

    func sink(_ ev: EncodeEvent) {
        switch mode {
        case .none:
            break
        case .human:
            printHuman(ev)
        case .json:
            printJSONLine(ev)
        }

        // Always write JSONL to the progress file when provided (independent of stdout mode).
        if fileHandle != nil {
            writeJSONLineToFile(ev)

            // Flush periodically, and always on terminal events.
            if isTerminal(ev) || shouldFlushNow() {
                flushFile()
            }
        }
    }

    // MARK: - Human

    private func printHuman(_ ev: EncodeEvent) {
        switch ev {
        case .phase(let p):
            writeHumanLine("Phase: \(p.rawValue)")
        case .warning(let s):
            writeHumanLine("Warning: \(s)")
        case .progress(let pr):
            let pct = Int((pr.fraction * 100.0).rounded())
            var parts: [String] = ["\(pct)%"]
            if let fps = pr.fps { parts.append(String(format: "%.1f fps", fps)) }
            if let eta = pr.etaSeconds { parts.append("ETA \(formatETA(eta))") }
            if let msg = pr.message, !msg.isEmpty { parts.append(msg) }
            writeHumanLine(parts.joined(separator: "  "))
        case .completed(let r):
            writeHumanLine("Done: \(r.outputURL.path)")
        case .failed(let e):
            writeHumanLine("Failed: \(e.message)")
        }
    }

    private func writeHumanLine(_ line: String) {
        // Single-line overwrite
        let padCount = max(0, lastHumanLineLen - line.count)
        let padded = line + String(repeating: " ", count: padCount)
        FileHandle.standardOutput.write(("\r" + padded).data(using: .utf8)!)
        lastHumanLineLen = line.count
    }

    private func formatETA(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    // MARK: - JSON lines (stdout)

    private func printJSONLine(_ ev: EncodeEvent) {
        guard let data = encodeJSONLine(ev) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }

    // MARK: - JSON lines (file)

    private func writeJSONLineToFile(_ ev: EncodeEvent) {
        guard let fh = fileHandle else { return }
        guard let data = encodeJSONLine(ev) else { return }

        do {
            try fh.write(contentsOf: data)
            try fh.write(contentsOf: Data([0x0A])) // "\n"
        } catch {
            dlog("Failed to write progress JSONL: \(error)")
        }
    }

    private func flushFile() {
        guard let fh = fileHandle else { return }
        do {
            try fh.synchronize()
        } catch {
            dlog("Failed to synchronize progress file: \(error)")
        }
        lastFlushWall = Date().timeIntervalSince1970
    }

    private func shouldFlushNow() -> Bool {
        let now = Date().timeIntervalSince1970
        return (now - lastFlushWall) >= flushEverySeconds
    }

    private func isTerminal(_ ev: EncodeEvent) -> Bool {
        switch ev {
        case .completed, .failed:
            // Terminal for a single media encode (file_done in JSONL)
            return true
        default:
            return false
        }
    }

    // MARK: - Encode JSON object

    private func encodeJSONLine(_ ev: EncodeEvent) -> Data? {
        var obj: [String: Any] = ["ts": Date().timeIntervalSince1970]

        switch ev {
        case .phase(let p):
            obj["type"] = "phase"
            obj["value"] = p.rawValue

        case .warning(let s):
            obj["type"] = "warning"
            obj["message"] = s

        case .progress(let pr):
            obj["type"] = "progress"
            obj["fraction"] = pr.fraction
            if let v = pr.framesDone { obj["framesDone"] = v }
            if let v = pr.framesTotal { obj["framesTotal"] = v }
            if let v = pr.secondsDone { obj["secDone"] = v }
            if let v = pr.secondsTotal { obj["secTotal"] = v }
            if let v = pr.fps { obj["fps"] = v }
            if let v = pr.etaSeconds { obj["eta"] = v }
            if let v = pr.bytesWritten { obj["bytes"] = v }
            if let v = pr.message { obj["message"] = v }

        case .completed(let r):
            obj["type"] = "file_done"
            obj["ok"] = true
            obj["output"] = r.outputURL.path
            if let d = r.durationSeconds { obj["duration"] = d }
            if let f = r.framesEncoded { obj["frames"] = f }

        case .failed(let e):
            obj["type"] = "file_done"
            obj["ok"] = false
            obj["code"] = e.code.rawValue
            obj["message"] = e.message
        }

        return try? JSONSerialization.data(withJSONObject: obj, options: [])
    }
    
    func emitBatchDone(ok: Bool, itemsEncoded: Int? = nil) {
        guard let fh = fileHandle else { return }

        var obj: [String: Any] = [
            "ts": Date().timeIntervalSince1970,
            "type": "batch_done",
            "ok": ok
        ]
        if let n = itemsEncoded { obj["itemsEncoded"] = n }

        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else { return }

        do {
            try fh.write(contentsOf: data)
            try fh.write(contentsOf: Data([0x0A]))
            try fh.synchronize()   // important: make tailer see it immediately
        } catch {
            // best effort
        }
    }
}
