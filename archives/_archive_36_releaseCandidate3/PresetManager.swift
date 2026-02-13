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
    
    private init() {}
    
    // MARK: - Preset Storage
    
    /// Load all saved presets from disk
    func loadPresets() -> [EncodingPreset] {
        do {
            let url = try presetsURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                return createDefaultPresets()
            }
            
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let presets = try decoder.decode([EncodingPreset].self, from: data)
            
            // Ensure we always have default presets if none exist
            return presets.isEmpty ? createDefaultPresets() : presets
        } catch {
            print("⚠️ Failed to load presets: \(error)")
            return createDefaultPresets()
        }
    }
    
    /// Reset all presets to factory defaults
    func resetToDefaults() throws {
        let defaultPresets = createDefaultPresets()
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
        
        private func createDefaultPresets() -> [EncodingPreset] {
            var presets: [EncodingPreset] = []
            
            // 1. Default preset - Local, CRF 18, all panels hidden
            var defaultSettings = Settings()
            defaultSettings.runMode = .localFFmpeg
            defaultSettings.qualityCRF = 18
            defaultSettings.containerFormat = .mov
            defaultSettings.outputSuffix = "-HEVC"
            // All panels hidden (collapsed)
            defaultSettings.presetsExpanded = true      // Keep presets panel open
            defaultSettings.generalExpanded = false
            defaultSettings.scaleExpanded = false
            defaultSettings.nclcExpanded = false
            defaultSettings.overlaysExpanded = false
            defaultSettings.deadlineExpanded = false
            presets.append(EncodingPreset(name: "Default", settings: defaultSettings.forPreset()))
            
            // 2. High Quality (Local) preset
            var highQualityLocalSettings = Settings()
            highQualityLocalSettings.runMode = .localFFmpeg
            highQualityLocalSettings.qualityCRF = 15
            highQualityLocalSettings.containerFormat = .mov
            highQualityLocalSettings.outputSuffix = "-HEVC"
            // All panels hidden
            highQualityLocalSettings.presetsExpanded = true
            highQualityLocalSettings.generalExpanded = false
            highQualityLocalSettings.scaleExpanded = false
            highQualityLocalSettings.nclcExpanded = false
            highQualityLocalSettings.overlaysExpanded = false
            highQualityLocalSettings.deadlineExpanded = false
            presets.append(EncodingPreset(name: "High Quality (Local)", settings: highQualityLocalSettings.forPreset()))
            
            // 3. Small File Size (Local) preset
            var smallFileSettings = Settings()
            smallFileSettings.runMode = .localFFmpeg
            smallFileSettings.qualityCRF = 28
            smallFileSettings.containerFormat = .mov
            smallFileSettings.outputSuffix = "-HEVC"
            // All panels hidden
            smallFileSettings.presetsExpanded = true
            smallFileSettings.generalExpanded = false
            smallFileSettings.scaleExpanded = false
            smallFileSettings.nclcExpanded = false
            smallFileSettings.overlaysExpanded = false
            smallFileSettings.deadlineExpanded = false
            presets.append(EncodingPreset(name: "Small File Size (Local)", settings: smallFileSettings.forPreset()))
            
            // 4. Review Half-Size (Local) preset
            var reviewHalfLocalSettings = Settings()
            reviewHalfLocalSettings.runMode = .localFFmpeg
            reviewHalfLocalSettings.qualityCRF = 20
            reviewHalfLocalSettings.containerFormat = .mov
            reviewHalfLocalSettings.outputSuffix = "-HEVC"
            reviewHalfLocalSettings.scale = .half
            reviewHalfLocalSettings.scaleSuffix = "-HALF"
            // Text overlay - Frames in lower right
            reviewHalfLocalSettings.burnInFrames = true
            reviewHalfLocalSettings.burnInFramesPosition = .lowerRight
            reviewHalfLocalSettings.overlayTextColorHex = "#FFFFFF"     // White text
            reviewHalfLocalSettings.overlayTextColorAlpha = 1.0
            reviewHalfLocalSettings.overlayBoxEnabled = true
            reviewHalfLocalSettings.overlayBoxColorHex = "#000000"      // Black box
            reviewHalfLocalSettings.overlayBoxColorAlpha = 0.80
            // All panels hidden
            reviewHalfLocalSettings.presetsExpanded = true
            reviewHalfLocalSettings.generalExpanded = false
            reviewHalfLocalSettings.scaleExpanded = false
            reviewHalfLocalSettings.nclcExpanded = false
            reviewHalfLocalSettings.overlaysExpanded = false
            reviewHalfLocalSettings.deadlineExpanded = false
            presets.append(EncodingPreset(name: "Review Half-Size (Local)", settings: reviewHalfLocalSettings.forPreset()))
            
            // 5. High Quality (Remote, CGS) preset
            var highQualityRemoteSettings = Settings()
            highQualityRemoteSettings.runMode = .remoteDeadline
            highQualityRemoteSettings.qualityCRF = 15
            highQualityRemoteSettings.containerFormat = .mov
            highQualityRemoteSettings.outputSuffix = "-HEVC"
            // Deadline settings for CGS
            highQualityRemoteSettings.pool = "cgss"
            highQualityRemoteSettings.secondaryPool = "cgss"
            highQualityRemoteSettings.group = "ae-cwg"
            highQualityRemoteSettings.priority = 50
            // All panels hidden
            highQualityRemoteSettings.presetsExpanded = true
            highQualityRemoteSettings.generalExpanded = false
            highQualityRemoteSettings.scaleExpanded = false
            highQualityRemoteSettings.nclcExpanded = false
            highQualityRemoteSettings.overlaysExpanded = false
            highQualityRemoteSettings.deadlineExpanded = false
            presets.append(EncodingPreset(name: "High Quality (Remote, CGS)", settings: highQualityRemoteSettings.forPreset()))
            
            // 6. Review Half-Size (Remote, CGS) preset
            var reviewHalfRemoteSettings = Settings()
            reviewHalfRemoteSettings.runMode = .remoteDeadline
            reviewHalfRemoteSettings.qualityCRF = 20
            reviewHalfRemoteSettings.containerFormat = .mov
            reviewHalfRemoteSettings.outputSuffix = "-HEVC"
            reviewHalfRemoteSettings.scale = .half
            reviewHalfRemoteSettings.scaleSuffix = "-HALF"
            // Text overlay - Frames in lower right
            reviewHalfRemoteSettings.burnInFrames = true
            reviewHalfRemoteSettings.burnInFramesPosition = .lowerRight
            reviewHalfRemoteSettings.overlayTextColorHex = "#FFFFFF"     // White text
            reviewHalfRemoteSettings.overlayTextColorAlpha = 1.0
            reviewHalfRemoteSettings.overlayBoxEnabled = true
            reviewHalfRemoteSettings.overlayBoxColorHex = "#000000"      // Black box
            reviewHalfRemoteSettings.overlayBoxColorAlpha = 0.80
            // Deadline settings for CGS (same as High Quality)
            reviewHalfRemoteSettings.pool = "cgss"
            reviewHalfRemoteSettings.secondaryPool = "cgss"
            reviewHalfRemoteSettings.group = "ae-cwg"
            reviewHalfRemoteSettings.priority = 50
            // All panels hidden
            reviewHalfRemoteSettings.presetsExpanded = true
            reviewHalfRemoteSettings.generalExpanded = false
            reviewHalfRemoteSettings.scaleExpanded = false
            reviewHalfRemoteSettings.nclcExpanded = false
            reviewHalfRemoteSettings.overlaysExpanded = false
            reviewHalfRemoteSettings.deadlineExpanded = false
            presets.append(EncodingPreset(name: "Review Half-Size (Remote, CGS)", settings: reviewHalfRemoteSettings.forPreset()))
            
            return presets
        }
    
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
