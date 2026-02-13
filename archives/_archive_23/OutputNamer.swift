// =============================
// File: OutputNamer.swift
// =============================
import Foundation

enum OutputNamer {
    /// Builds an output URL next to the input, placing the NCLC label **before** the compression suffix.
    /// De-dupes by adding `_2`, `_3`, ... if the candidate already exists (including when it equals the source).
    static func suggestedOutputURL(for input: URL, settings: Settings) -> URL {
        let dir  = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let ext  = input.pathExtension.isEmpty ? "mov" : input.pathExtension

        // Filename pieces
        func norm(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return "" }
            return t.hasPrefix("-") ? t : "-" + t
        }
        let color = norm(settings.nclcFilenameLabel)        // comes first
        let comp  = norm(settings.outputSuffix)             // then compression suffix

        let candidate = dir.appendingPathComponent("\(base)\(color)\(comp)").appendingPathExtension(ext)

        // If candidate path does not exist, use it.
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        // Else de-dupe: add _2, _3, ...
        var i = 2
        while true {
            let c = dir.appendingPathComponent("\(base)\(color)\(comp)_\(i)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: c.path) {
                return c
            }
            i += 1
        }
    }
}
