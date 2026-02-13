//
//  PresetViewModel.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/23/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - PresetViewModel

final class PresetViewModel: ObservableObject {
    private let core = AppCore.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // If you had Combine pipelines here, keep them; otherwise this init is fine.
    }

    // MARK: Display helpers

    /// Returns a display name for a preset, optionally marking the current one.
    func presetDisplayName(_ preset: EncodingPreset, isCurrent: Bool) -> String {
        isCurrent ? "\(preset.name) ✓" : preset.name
    }

    // MARK: Apply / Save / Delete / Export

    /// Applies the given preset to the app state.
    /// If you later add a centralized apply API, swap the internals here.
    func applyPreset(_ preset: EncodingPreset) {
        core.settings = preset.settings
        core.settings.selectedPresetName = preset.name
    }

    /// Validate a user-entered preset name.
    func validatePresetName(_ name: String) -> (valid: Bool, reason: String?) {
        PresetManager.isValidPresetName(name)
    }

    /// Simple policy for whether a preset can be deleted.
    func canDeletePreset(_ name: String) -> Bool {
        // Deletable if the name is non-empty (no hidden “system preset” rule here)
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Saves the provided settings under the given preset name.
    /// Ensures the *provided* Settings are applied before persisting (important for imports).
    func savePreset(name: String, settings: Settings) throws {
        core.settings = settings
        try core.saveCurrentAsPreset(name: name)
    }

    func deletePreset(_ preset: EncodingPreset) throws {
        try core.deletePreset(name: preset.name)
    }

    func exportDroplet(_ preset: EncodingPreset) {
        core.exportDroplet(name: preset.name)
    }

    // MARK: - Import (Droplet / JSON / Script)

    /// Imports a preset from a MrHEVC droplet (.app), a preset .json file, or a compiled AppleScript .scpt.
    /// - Returns: (Settings payload, suggested preset name).
    func importDroplet(from url: URL) throws -> (Settings, String) {
        var (settings, name) = try DropletImporter.loadPreset(from: url)

        // ✅ Apply sticky fallback for Deadline Pools/Group.
        // Keeps droplet values if present; fills from machine stickies if missing/"none".
        settings = PreferencesService.shared.applyStickyDeadlineFallback(to: settings)

        return (settings, name)
    }
}

// MARK: - Private import helpers

private enum DropletImportError: LocalizedError {
    case unsupportedSelection
    case presetJSONNotFound
    case decodeFailed
    case toolUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            return "Please select a MrHEVC droplet (.app) or a preset .json file."
        case .presetJSONNotFound:
            return "Could not find a preset inside that droplet."
        case .decodeFailed:
            return "The preset could not be decoded."
        case .toolUnavailable(let name):
            return "\(name) is not available on this system."
        }
    }
}

private enum DropletImporter {
    /// Returns (Settings payload, suggested preset name)
    static func loadPreset(from url: URL) throws -> (Settings, String) {
        let ext = url.pathExtension.lowercased()
        let baseName = url.deletingPathExtension().lastPathComponent

        switch ext {
        case "json":
            let data = try Data(contentsOf: url)
            let settings = try JSONDecoder().decode(Settings.self, from: data)
            return (settings, baseName)

        case "app":
            // Preferred: bundled JSON in newer droplets
            let resJSON = url.appendingPathComponent("Contents/Resources/mrhevc_preset.json")
            if FileManager.default.fileExists(atPath: resJSON.path) {
                let data = try Data(contentsOf: resJSON)
                let settings = try JSONDecoder().decode(Settings.self, from: data)
                return (settings, baseName)
            }
            // Fallback: decompile AppleScript and extract `property presetData : "…"`
            let mainScpt = url.appendingPathComponent("Contents/Resources/Scripts/main.scpt")
            guard FileManager.default.fileExists(atPath: mainScpt.path) else {
                throw DropletImportError.presetJSONNotFound
            }
            let source = try runOsadecompile(on: mainScpt)
            guard let json = extractPresetJSON(from: source),
                  let data = json.data(using: .utf8),
                  let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
                throw DropletImportError.decodeFailed
            }
            return (settings, baseName)

        case "scpt":
            let source = try runOsadecompile(on: url)
            guard let json = extractPresetJSON(from: source),
                  let data = json.data(using: .utf8),
                  let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
                throw DropletImportError.decodeFailed
            }
            return (settings, baseName)

        default:
            throw DropletImportError.unsupportedSelection
        }
    }

    // MARK: AppleScript decompile + JSON extract

    private static func runOsadecompile(on url: URL) throws -> String {
        let tool = "/usr/bin/osadecompile"
        guard FileManager.default.isExecutableFile(atPath: tool) else {
            throw DropletImportError.toolUnavailable("osadecompile")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tool)
        proc.arguments = [url.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Extracts JSON from a decompiled AppleScript line like:
    ///   property presetData : "…json…"
    private static func extractPresetJSON(from decompiledSource: String) -> String? {
        guard let line = decompiledSource
            .components(separatedBy: .newlines)
            .first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("property presetData :") })
        else { return nil }

        guard let firstQuote = line.firstIndex(of: "\""),
              let lastQuote  = line.lastIndex(of: "\""),
              firstQuote < lastQuote else { return nil }

        var json = String(line[line.index(after: firstQuote)..<lastQuote])
        // Unescape common sequences if osadecompile left them escaped
        json = json.replacingOccurrences(of: "\\\"", with: "\"")
        json = json.replacingOccurrences(of: "\\n", with: "\n")
        return json
    }
}
