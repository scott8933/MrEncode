//
//  ProgressTailer.swift
//  MrEncodeProgress
//
//  Created by scott ulrich on 2/5/26.
//

import Foundation

final class ProgressTailer {
    private let url: URL
    private var fh: FileHandle?
    private var offset: UInt64 = 0
    private var buffer = Data()
    private var timer: Timer?

    var onEvent: ((ProgressEvent) -> Void)?
    var onBatchDone: ((_ ok: Bool) -> Void)?


    init(url: URL) { self.url = url }

    private var debugEnabled: Bool {
        ProcessInfo.processInfo.environment["MR_ENCODE_DEBUG_PROGRESS_TAILER"] == "1"
    }

    private func dlog(_ msg: String) {
        guard debugEnabled else { return }
        FileHandle.standardError.write(("[ProgressTailer] \(msg)\n").data(using: .utf8)!)
    }

    func start() {
        stop()

        // File should be pre-created by droplet/CLI; retry briefly if not
        var attempts = 0

        timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }

            if self.fh == nil {
                do {
                    self.fh = try FileHandle(forReadingFrom: self.url)
                    self.offset = 0
                    self.buffer.removeAll(keepingCapacity: true)
                    self.dlog("Opened file: \(self.url.path)")
                } catch {
                    attempts += 1
                    if attempts > 50 { // ~10s timeout
                        self.dlog("Timeout waiting for file: \(self.url.path)")
                        t.invalidate()
                    }
                    return
                }
            }

            self.readNew()
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        try? fh?.close()
        fh = nil
        offset = 0
        buffer.removeAll(keepingCapacity: true)
    }

    private func readNew() {
        do {
            // Get file size
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let n = attrs[.size] as? NSNumber else { return }
            let size = n.uint64Value

            // If file got truncated/recreated, reset state so we can read again.
            if size < offset {
                offset = 0
                buffer.removeAll(keepingCapacity: true)
            }

            guard size > offset else { return }

            // CLOSE AND REOPEN to see latest writes (preserve the behavior that worked)
            try? fh?.close()
            fh = try FileHandle(forReadingFrom: url)

            try fh?.seek(toOffset: offset)

            let toRead64 = size - offset
            let toRead = toRead64 > UInt64(Int.max) ? Int.max : Int(toRead64)

            let data = try fh?.read(upToCount: toRead) ?? Data()

            // Advance offset by actual bytes read (avoids skipping if file grows mid-read)
            offset += UInt64(data.count)

            guard !data.isEmpty else { return }

            buffer.append(data)

            let newline = Data([0x0A])

            while let nl = buffer.firstRange(of: newline) {
                let line = buffer.subdata(in: 0..<nl.lowerBound)
                buffer.removeSubrange(0..<nl.upperBound)

                guard
                    let s = String(data: line, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    !s.isEmpty
                else { continue }

                let lineData = Data(s.utf8)

                if let ev = try? JSONDecoder().decode(ProgressEvent.self, from: lineData) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onEvent?(ev)
                    }

                    // If batch_done decodes as ProgressEvent (likely), read ok from JSON directly.
                    if ev.type.lowercased() == "batch_done" {
                        let ok: Bool = {
                            if
                                let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
                                let ok = obj["ok"] as? Bool
                            {
                                return ok
                            }
                            return true
                        }()

                        DispatchQueue.main.async { [weak self] in
                            self?.onBatchDone?(ok)
                        }
                    }

                    continue
                }

                // Fallback decode (handles batch_done even if ProgressEvent decode fails)
                if
                    let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
                    let type = obj["type"] as? String,
                    type.lowercased() == "batch_done"
                {
                    let ok = (obj["ok"] as? Bool) ?? true
                    DispatchQueue.main.async { [weak self] in
                        self?.onBatchDone?(ok)
                    }
                    continue
                }

                // Ignore invalid/partial JSON lines (writer mid-flush). Keep tailing.
                continue
            }
        } catch {
            // Optional debug only
            dlog("readNew error: \(error)")
            return
        }
    }


}
