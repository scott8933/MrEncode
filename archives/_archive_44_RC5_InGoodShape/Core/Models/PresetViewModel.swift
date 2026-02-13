//
//  PresetViewModel.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/23/25.
//


//
// MARK: - PresetViewModel.swift
//

import Foundation
import SwiftUI
import Combine

/// Handles preset-specific UI logic and validation
class PresetViewModel: ObservableObject {
    private let core = AppCore.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Subscribe to core changes
        core.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }
    
    // MARK: - Preset Display Logic
    
    func presetDisplayName(_ preset: EncodingPreset, isCurrent: Bool) -> String {
        return isCurrent ? "✓ \(preset.name)" : preset.name
    }
    
    func presetSummary(_ preset: EncodingPreset) -> String {
        let settings = preset.settings
        var parts: [String] = []
        
        parts.append("CRF \(settings.qualityCRF)")
        
        if settings.scale != .oneToOne {
            parts.append(settings.scale.rawValue)
        }
        
        if settings.runMode == .remoteDeadline {
            parts.append("Remote")
        } else {
            parts.append("Local")
        }
        
        return parts.joined(separator: " • ")
    }
    
    func overlaysSummary(_ settings: Settings) -> String {
        var overlays: [String] = []
        
        if settings.burnInFrames {
            overlays.append("Frames")
        }
        
        if settings.burnInTimecode {
            overlays.append("Timecode")
        }
        
        if settings.burnInFilename {
            overlays.append("Filename")
        }
        
        return overlays.isEmpty ? "None" : overlays.joined(separator: ", ")
    }
    
    // MARK: - Validation Logic
    
    func validatePresetName(_ name: String) -> (valid: Bool, reason: String?) {
        return PresetManager.isValidPresetName(name)
    }
    
    func canDeletePreset(_ name: String) -> Bool {
        return name != "Default" && name != "Good Quality (Local)"
    }
    
    func canRenamePreset(_ name: String) -> Bool {
        return name != "Default" && name != "Good Quality (Local)"
    }
    
    // MARK: - Preset Actions
    
    func applyPreset(_ preset: EncodingPreset) {
        core.applyPreset(name: preset.name)
    }
    
    func savePreset(name: String, settings: Settings) throws {
        try core.saveCurrentAsPreset(name: name)
    }
    
    func deletePreset(_ preset: EncodingPreset) throws {
        try core.deletePreset(name: preset.name)
    }
    
    func exportDroplet(_ preset: EncodingPreset) {
        core.exportDroplet(name: preset.name)
    }
}
