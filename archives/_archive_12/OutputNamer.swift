//
//  OutputNamer.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/4/25.
//


// =============================
// File: OutputNamer.swift
// =============================
import Foundation

enum OutputNamer {

    /// Builds an output URL next to the input, inserting the user suffix before the extension.
    /// If the path already exists, appends _2, _3, ... to avoid overwriting.
    static func suggestedOutputURL(for input: URL, settings: Settings) -> URL {
        return outputURL(for: input, suffix: settings.outputSuffix)
    }

    static func outputURL(for input: URL, suffix: String) -> URL {
        let dir  = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let ext  = input.pathExtension.isEmpty ? "mov" : input.pathExtension

        let cleanSuffix = suffix.isEmpty ? "" : suffix
        var candidate = dir.appendingPathComponent("\(base)\(cleanSuffix)").appendingPathExtension(ext)

        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        // De-dupe: add _2, _3, ...
        var i = 2
        while true {
            let c = dir.appendingPathComponent("\(base)\(cleanSuffix)_\(i)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: c.path) {
                return c
            }
            i += 1
        }
    }
}
