//
//  PreferencesService.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/23/25.
//


//
// MARK: - PreferencesService.swift
//

import Foundation
import SwiftUI

/// Handles settings persistence and loading
class PreferencesService {
    static let shared = PreferencesService()
    
    private let store = PreferencesStore()
    
    private init() {}
    
    func loadSettings() -> Settings {
        do {
            var settings = try store.load()
            settings.coerceDropdownDefaultsTopFirst()
            return settings
        } catch {
            print("⚠️ Preferences load failed, using defaults: \(error)")
            var settings = Settings()
            settings.coerceDropdownDefaultsTopFirst()
            return settings
        }
    }
    
    func saveSettings(_ settings: Settings) {
        do {
            try store.save(settings)
        } catch {
            print("⚠️ Preferences save failed: \(error)")
        }
    }
}
