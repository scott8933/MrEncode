//
//  PresetManager.swift
//  MrHEVC
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
    
    private init() {}
    
    // MARK: - Preset Storage
    
    /// Load all saved presets from disk
    func loadPresets() -> [EncodingPreset] {
        do {
            let url = try presetsURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                return factoryEncodingPresets()
            }
            
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let presets = try decoder.decode([EncodingPreset].self, from: data)
            
            // Ensure we always have default presets if none exist
            return presets.isEmpty ? factoryEncodingPresets() : presets
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
    func exportDroplet(name: String, settings: Settings, to url: URL) throws {
        try DropletBuilder.shared.createDroplet(presetName: name, settings: settings, at: url)
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
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
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
        
    // MARK: - Default Presets

    private struct FactoryPreset: Codable {
        let name: String
        let settings: Settings
    }

    private func factoryEncodingPresets() -> [EncodingPreset] {
        do {
            let definitions = try loadFactoryPresetDefinitions()
            return definitions.map { EncodingPreset(name: $0.name, settings: $0.settings) }
        } catch {
            fatalError("Factory preset definitions missing or corrupt: \(error)")
        }
    }

    private func loadFactoryPresetDefinitions() throws -> [FactoryPreset] {
        for bundle in factoryBundles() {
            if let url = bundle.url(forResource: factoryPresetsResource, withExtension: factoryPresetsExtension) {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode([FactoryPreset].self, from: data)
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
        let dir = appSupport.appendingPathComponent("MrHEVC", isDirectory: true)
        
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
