// =============================
// File: OutputNamer.swift
// =============================
import Foundation

enum OutputNamer {
    /// Builds an output URL next to the input, assembling suffix parts (NCLC / Scale / Compression)
    /// in the user-chosen order (Settings.filenameOrder). Any blank parts are skipped.
    /// De-dupes by adding `_2`, `_3`, ... if the candidate already exists (including when it equals the source).
    static func suggestedOutputURL(for input: URL, settings: Settings) -> URL {
        let dir  = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        
        // Use the selected container format extension
        let ext = settings.containerFormat.fileExtension

        // Normalize a suffix fragment: trim and ensure a leading hyphen if non-empty.
        func norm(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return "" }
            return t.hasPrefix("-") ? t : "-" + t
        }

        // Map each filename part to its current (normalized) text.
        func piece(for part: FilenamePart) -> String {
            switch part {
            case .nclc:        return norm(settings.nclcFilenameLabel)
            case .scale:       return norm(settings.scaleSuffix)
            case .compression: return norm(settings.outputSuffix)
            }
        }

        // Use the saved order; if somehow empty, fall back to the default order.
        let order: [FilenamePart] = settings.filenameOrder.isEmpty
            ? [.nclc, .scale, .compression]
            : unique(settings.filenameOrder)  // guard against accidental duplicates

        let parts = order.map(piece).joined()
        let baseName = "\(base)\(parts)"

        let candidate = dir.appendingPathComponent(baseName).appendingPathExtension(ext)

        // If candidate path does not exist, use it.
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        // Else de-dupe: add _2, _3, ...
        var i = 2
        while true {
            let deDuped = dir.appendingPathComponent("\(baseName)_\(i)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: deDuped.path) {
                return deDuped
            }
            i += 1
        }
    }

    // Ensure we don't process duplicate parts if they ever sneak into settings.filenameOrder
    private static func unique<T: Hashable>(_ array: [T]) -> [T] {
        var seen = Set<T>()
        var result: [T] = []
        for x in array where !seen.contains(x) {
            seen.insert(x)
            result.append(x)
        }
        return result
    }
}
