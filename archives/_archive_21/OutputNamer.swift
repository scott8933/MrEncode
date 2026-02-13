// =============================
// File: OutputNamer.swift
// =============================
import Foundation

enum OutputNamer {

    static func reuseOrSuggest(for item: MediaItem, settings: Settings) -> URL {
        if let prev = item.finalOutputURL { return prev }
        return suggestedOutputURL(for: item.url, settings: settings)
    }

    static func suggestedOutputURL(for input: URL, settings: Settings) -> URL {
        return outputURL(for: input, suffix: settings.outputSuffix)
    }

    static func outputURL(for input: URL, suffix: String) -> URL {
        let dir  = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let ext  = input.pathExtension.isEmpty ? "mov" : input.pathExtension
        let clean = suffix

        var candidate = dir.appendingPathComponent("\(base)\(clean)").appendingPathExtension(ext)
        if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }

        var i = 2
        while true {
            let c = dir.appendingPathComponent("\(base)\(clean)_\(i)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: c.path) { return c }
            i += 1
        }
    }
}
