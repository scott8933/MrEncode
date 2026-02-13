// =============================
// File: OutputNamer.swift
// =============================
import Foundation

enum OutputNamer {

    /// Build the suggested output URL using the user’s labels in order:
    /// [NCLC Color Label] then [Compression Filename Suffix]
    static func suggestedOutputURL(for input: URL, settings: Settings) -> URL {
        let dir  = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let ext  = input.pathExtension.isEmpty ? "mov" : input.pathExtension.lowercased()

        let color = normalizeLabel(settings.nclcFilenameLabel) // appears first
        let comp  = normalizeLabel(settings.outputSuffix)      // then compression suffix

        let name = base + color + comp + "." + ext
        return dir.appendingPathComponent(name)
    }

    /// Normalizes a user-entered label/suffix:
    /// - trims whitespace
    /// - ensures a single leading hyphen (if non-empty)
    private static func normalizeLabel(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        let h = t.hasPrefix("-") ? t : "-" + t
        return h.replacingOccurrences(of: "--", with: "-") // small cleanup in case
    }
}
