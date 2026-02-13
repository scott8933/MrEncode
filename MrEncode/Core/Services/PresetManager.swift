//
//  PresetManager.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/18/25.
//


// =============================
// File: PresetManager.swift - Preset and Droplet Management
// =============================

import Foundation
import AppKit

final class PresetManager {
    static let shared = PresetManager()
    
    private let presetsFilename = "presets.json"
    private let factoryPresetsResource = "default_presets"
    private let factoryPresetsExtension = "json"
    private let factoryPrefsResource = "default_prefs"
    private let factoryPrefsExtension = "json"

    
    private init() {}
    
    // MARK: - Preset Storage
    
    /// Load all saved presets from disk
    func loadPresets() -> [EncodingPreset] {
        do {
            let url = try presetsURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                // First run: load bundled defaults (has real authored JSON keys)
                return loadBundledDefaultPresets()
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()

            // Load as raw JSON first
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let arr = obj as? [[String: Any]] else {
                throw NSError(
                    domain: "PresetManager",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "presets.json root is not an array of objects"]
                )
            }

            var out: [EncodingPreset] = []
            out.reserveCapacity(arr.count)

            for presetObj in arr {
                let name = (presetObj["name"] as? String) ?? "Unnamed Preset"

                // 👇 RAW settings as authored in JSON (source of truth for Modified)
                let rawSettings = presetObj["settings"] as? [String: Any] ?? [:]

                // 👇 Runtime settings (defaults merged for safety)
                let settings = try decodeSettingsMergingFactoryDefaults(
                    from: rawSettings,
                    decoder: decoder
                )

                var preset = EncodingPreset(name: name, settings: settings)
                preset.rawSettings = rawSettings   // 👈 THIS is the key line

                out.append(preset)
            }

            return out.isEmpty ? factoryEncodingPresets() : out

        } catch {
            print("⚠️ Failed to load presets: \(error)")
            return factoryEncodingPresets()
        }
    }

    
    /// Reset all presets to factory defaults
    func resetToDefaults() throws {
        let defaultPresets = factoryEncodingPresets()
        try savePresets(defaultPresets)
    }
    
    /// Save presets to disk
    func savePresets(_ presets: [EncodingPreset]) throws {
        let url = try presetsURL(createDirIfNeeded: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(presets)
        try data.write(to: url, options: [.atomic])
    }
    
    /// Add or update a preset
    func savePreset(name: String, settings: Settings) throws {
        var presets = loadPresets()
        
        // Check if preset with this name already exists
        if let existingIndex = presets.firstIndex(where: { $0.name == name }) {
            // Update existing preset
            presets[existingIndex].updateSettings(settings.forPreset())
        } else {
            // Create new preset
            let newPreset = EncodingPreset(name: name, settings: settings.forPreset())
            presets.append(newPreset)
        }
        
        try savePresets(presets)
    }
    
    /// Delete a preset by name
    func deletePreset(name: String) throws {
        var presets = loadPresets()
        presets.removeAll { $0.name == name }
        try savePresets(presets)
    }
    
    /// Get a preset by name
    func getPreset(name: String) -> EncodingPreset? {
        return loadPresets().first { $0.name == name }
    }
    
    /// Rename a preset
    func renamePreset(oldName: String, newName: String) throws {
        var presets = loadPresets()
        
        // Check if new name already exists
        if presets.contains(where: { $0.name == newName }) {
            throw PresetError.nameAlreadyExists
        }
        
        // Find and rename
        guard let index = presets.firstIndex(where: { $0.name == oldName }) else {
            throw PresetError.presetNotFound
        }
        
        presets[index].name = newName
        presets[index].modifiedDate = Date()
        
        try savePresets(presets)
    }
    
    // MARK: - Droplet Export (Updated to use DropletBuilder)
    
    /// Export settings as a droplet application
    func createDroplet(
        presetName: String,
        settings: Settings,
        at outputURL: URL,
        extraCLIArgs: [String] = []
    ) throws {
        try DropletBuilder.shared.createDroplet(
            presetName: presetName,
            settings: settings,
            at: outputURL,
            extraCLIArgs: extraCLIArgs
        )
    }
    
    /// Show save dialog for droplet export
    func showDropletExportDialog(presetName: String, settings: Settings, completion: @escaping (Bool) -> Void) {
        DropletBuilder.shared.showCreateDropletDialog(presetName: presetName, settings: settings, completion: completion)
    }
    
    /// Load droplet file from JSON (for command-line droplet mode)
    func loadDroplet(from url: URL) throws -> DropletFile {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        
        // Try to decode with version compatibility
        do {
            return try decoder.decode(DropletFile.self, from: data)
        } catch {
            // If direct decode fails, try to extract what we can
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let version = json["version"] as? Int {
                
                if version > 1 {
                    // Future version - try to decode what we can
                    print("⚠️ Droplet file is from a newer version (v\(version)). Some settings may be ignored.")
                }
                
                // Attempt partial decode by reconstructing compatible JSON
                throw error // For now, just re-throw; can add migration logic later
            }
            throw error
        }
    }
    
    // MARK: - Defaults-merge decoding (schema-safe presets)

    private func deepMerge(_ base: Any, _ overlay: Any) -> Any {
        if var b = base as? [String: Any], let o = overlay as? [String: Any] {
            for (k, ov) in o {
                if let bv = b[k] {
                    b[k] = deepMerge(bv, ov)
                } else {
                    b[k] = ov
                }
            }
            return b
        }
        // Arrays: overlay wins wholesale (predictable)
        if let o = overlay as? [Any] { return o }
        return overlay
    }

    private func loadFactoryPrefsDictionary() throws -> [String: Any] {
        for bundle in factoryBundles() {
            if let url = bundle.url(forResource: factoryPrefsResource, withExtension: factoryPrefsExtension) {
                let data = try Data(contentsOf: url)
                let obj = try JSONSerialization.jsonObject(with: data, options: [])
                guard let dict = obj as? [String: Any] else {
                    throw NSError(domain: "PresetManager", code: 20, userInfo: [
                        NSLocalizedDescriptionKey: "\(factoryPrefsResource).\(factoryPrefsExtension) root is not an object"
                    ])
                }
                return dict
            }
        }
        throw NSError(domain: "PresetManager", code: 21, userInfo: [
            NSLocalizedDescriptionKey: "\(factoryPrefsResource).\(factoryPrefsExtension) not found in bundle"
        ])
    }

    private func decodeSettingsMergingFactoryDefaults(from settingsObj: Any, decoder: JSONDecoder) throws -> Settings {
        let factory = try loadFactoryPrefsDictionary()
        let merged = deepMerge(factory, settingsObj)
        let mergedData = try JSONSerialization.data(withJSONObject: merged, options: [])
        return try decoder.decode(Settings.self, from: mergedData)
    }

        
    // MARK: - Default Presets

    private struct FactoryPreset: Codable {
        let name: String
        let settings: Settings
    }

    private func factoryEncodingPresets() -> [EncodingPreset] {
        do {
            let definitions = try loadFactoryPresetDefinitions()
            let presets = definitions.map { EncodingPreset(name: $0.name, settings: $0.settings) }
            return presets.isEmpty ? safeFallbackPresets() : presets
        } catch {
            print("⚠️ Factory presets missing/corrupt; using Safe Default. Error: \(error)")
            return safeFallbackPresets()
        }
    }

    private func safeFallbackPresets() -> [EncodingPreset] {
        // Minimal “always boots” fallback even if bundle JSON is missing.
        let defaults = PreferencesService.shared.factoryDefaults()
        return [EncodingPreset(name: "Default", settings: defaults.forPreset())]
    }
    
    private func loadBundledDefaultPresets() -> [EncodingPreset] {
        do {
            guard let url = Bundle.main.url(forResource: "default_presets", withExtension: "json") else {
                return factoryEncodingPresets() // last resort
            }

            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()

            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let arr = obj as? [[String: Any]] else { return factoryEncodingPresets() }

            var out: [EncodingPreset] = []
            out.reserveCapacity(arr.count)

            for presetObj in arr {
                let name = (presetObj["name"] as? String) ?? "Unnamed Preset"
                let rawSettings = presetObj["settings"] as? [String: Any] ?? [:]

                let settings = try decodeSettingsMergingFactoryDefaults(from: rawSettings, decoder: decoder)

                var preset = EncodingPreset(name: name, settings: settings)
                preset.rawSettings = rawSettings
                out.append(preset)
            }

            return out.isEmpty ? factoryEncodingPresets() : out
        } catch {
            return factoryEncodingPresets()
        }
    }



    private func loadFactoryPresetDefinitions() throws -> [FactoryPreset] {
        for bundle in factoryBundles() {
            if let url = bundle.url(forResource: factoryPresetsResource, withExtension: factoryPresetsExtension) {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let obj = try JSONSerialization.jsonObject(with: data, options: [])
                guard let arr = obj as? [[String: Any]] else {
                    throw NSError(domain: "PresetManager", code: 5,
                                  userInfo: [NSLocalizedDescriptionKey: "default_presets.json root is not an array"])
                }

                var out: [FactoryPreset] = []
                out.reserveCapacity(arr.count)

                for presetObj in arr {
                    let name = (presetObj["name"] as? String) ?? "Unnamed Preset"
                    let settingsObj = presetObj["settings"] ?? [:]
                    let settings = try decodeSettingsMergingFactoryDefaults(from: settingsObj, decoder: decoder)
                    out.append(FactoryPreset(name: name, settings: settings))
                }

                return out
            }
        }
        throw NSError(domain: "PresetManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "default_presets.json not found in bundle"])
    }

    private func factoryBundles() -> [Bundle] {
        var bundles: [Bundle] = [Bundle.main]
        let locatorBundle = Bundle(for: BundleLocator.self)
        if locatorBundle.bundleURL != Bundle.main.bundleURL {
            bundles.append(locatorBundle)
        }
        return bundles
    }

    private final class BundleLocator {}
    
    
    // MARK: - File Paths
    
    private func presetsURL(createDirIfNeeded: Bool = false) throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = appSupport.appendingPathComponent("MrEncode", isDirectory: true)
        
        if createDirIfNeeded && !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        return dir.appendingPathComponent(presetsFilename)
    }
    
    /// Validate preset name for creation/rename
    static func isValidPresetName(_ name: String) -> (valid: Bool, reason: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return (false, "Name cannot be empty")
        }
        
        if trimmed.count > 50 {
            return (false, "Name too long (max 50 characters)")
        }
        
        // Check for invalid characters (file system safety)
        let invalidChars = CharacterSet(charactersIn: "/:*?\"<>|\\")
        if trimmed.rangeOfCharacter(from: invalidChars) != nil {
            return (false, "Name contains invalid characters")
        }
        
        // Reserved names
        let reserved = ["Default", "CON", "PRN", "AUX", "NUL"]
        if reserved.contains(trimmed) {
            return (false, "Name is reserved")
        }
        
        return (true, nil)
    }
}
