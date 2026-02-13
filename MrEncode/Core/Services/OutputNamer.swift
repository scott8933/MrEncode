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

        // Normalize a suffix fragment: trim only. UI is responsible for any leading separator.
        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Map each filename part to its current (normalized) text.
        func piece(for part: FilenamePart) -> String {
            let raw: String
            switch part {
            case .nclc:        raw = norm(settings.nclcFilenameLabel)
            case .scale:       raw = norm(settings.scaleSuffix)
            case .compression: raw = norm(settings.outputSuffix)
            case .overlays:    raw = norm(settings.overlaySuffix)
            }
            return raw.isEmpty ? "" : raw
        }

        // Use the saved order; if somehow empty, fall back to the default order.
        let defaultOrder: [FilenamePart] = [.nclc, .scale, .compression, .overlays]

        // Start from saved order (deduped), or default if empty
        var order = settings.filenameOrder.isEmpty ? defaultOrder : unique(settings.filenameOrder)

        // Auto-append any missing parts (e.g. older prefs that don't include newer cases)
        for part in defaultOrder where !order.contains(part) {
            order.append(part)
        }


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
