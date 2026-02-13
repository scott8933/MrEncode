//
//  PreferencesService.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/23/25.
//

import Foundation
import SwiftUI

/// Handles settings persistence and loading
final class PreferencesService {
    static let shared = PreferencesService()

    // Underlying on-disk store for full app Settings
    private let store = PreferencesStore()

    // Machine-local "sticky" Deadline picks live in UserDefaults
    private let defaults = UserDefaults.standard
    private enum Key {
        static let dlPool           = "deadline.sticky.pool"
        static let dlSecondaryPool  = "deadline.sticky.secondaryPool"
        static let dlGroup          = "deadline.sticky.group"
        static let dropletShowPopup = "droplet.export.showPopup"
        static let dropletPlayChime = "droplet.export.playChime"
    }

    private init() {}

    // MARK: - Public: App Settings IO

    /// Load app settings from disk, normalize dropdown defaults,
    /// and hydrate any missing Deadline pools/groups from sticky values.
    func loadSettings() -> Settings {
        do {
            let settings = try store.bootstrapUserPrefsIfNeeded()
            return normalize(settings)
        } catch {
            print("⚠️ Preferences load failed. Quarantining prefs and regenerating from factory defaults. Error: \(error)")

            if let quarantined = store.quarantineUserPrefsFile() {
                print("⚠️ Quarantined corrupt prefs to: \(quarantined.path)")
            }

            do {
                let defaults = try store.resetUserSettingsToFactoryDefaults()
                return normalize(defaults)
            } catch {
                // This should only happen if the app bundle is missing factory defaults.
                // That's not a user-prefs evolution issue; it's a packaging error.
                fatalError("Unable to load MrEncode factory defaults from app bundle: \(error)")
            }
        }
    }


    /// Save full app settings to disk (does not touch sticky values).
    func saveSettings(_ settings: Settings) {
        do {
            try store.save(settings)
        } catch {
            print("⚠️ Preferences save failed: \(error)")
        }
    }

    /// Snapshot of factory defaults bundled with the app.
    func factoryDefaults() -> Settings {
        do {
            var defaults = try store.loadFactoryDefaults()
            defaults.coerceDropdownDefaultsTopFirst()
            return defaults
        } catch {
            fatalError("Factory defaults are missing from the app bundle: \(error)")
        }
    }

    /// Overwrite the user's prefs file with the factory defaults.
    func resetSettingsToFactoryDefaults() -> Settings {
        do {
            let defaults = try store.resetUserSettingsToFactoryDefaults()
            return normalize(defaults)
        } catch {
            fatalError("Failed to reset MrEncode preferences to factory defaults: \(error)")
        }
    }

    private func normalize(_ settings: Settings) -> Settings {
        var normalized = settings
        normalized.coerceDropdownDefaultsTopFirst()
        normalized = applyStickyDeadlineFallback(to: normalized)
        return normalized
    }

    // MARK: - Sticky Deadline values (machine-local, not part of preset)

    /// The user's last chosen Deadline Pool on this Mac.
    var stickyPool: String {
        get { defaults.string(forKey: Key.dlPool) ?? "none" }
        set { defaults.set(newValue, forKey: Key.dlPool) }
    }

    /// The user's last chosen Deadline Secondary Pool on this Mac.
    var stickySecondaryPool: String {
        get { defaults.string(forKey: Key.dlSecondaryPool) ?? "none" }
        set { defaults.set(newValue, forKey: Key.dlSecondaryPool) }
    }

    /// The user's last chosen Deadline Group on this Mac.
    var stickyGroup: String {
        get { defaults.string(forKey: Key.dlGroup) ?? "none" }
        set { defaults.set(newValue, forKey: Key.dlGroup) }
    }

    /// Update sticky values from a given Settings object.
    /// Call this from UI `.onChange` handlers for pool/secondary/group,
    /// or any time you want to persist the latest picks locally.
    func updateSticky(from settings: Settings) {
        if !settings.pool.isNoneOrEmpty            { stickyPool = settings.pool }
        if !settings.secondaryPool.isNoneOrEmpty   { stickySecondaryPool = settings.secondaryPool }
        if !settings.group.isNoneOrEmpty           { stickyGroup = settings.group }
    }

    /// Apply sticky values to a Settings object IF those fields are empty/"none".
    /// This is used when loading settings or after applying a preset that
    /// didn't include pool selections; it preserves explicit values.
    func applyStickyDeadlineFallback(to settings: Settings) -> Settings {
        var s = settings
        if s.pool.isNoneOrEmpty          { s.pool = stickyPool }
        if s.secondaryPool.isNoneOrEmpty { s.secondaryPool = stickySecondaryPool }
        if s.group.isNoneOrEmpty         { s.group = stickyGroup }
        return s
    }
    
    // MARK: - Droplet Export Options (machine-local)

    /// Whether exported droplets should show a completion popup by default.
    var dropletExportShowPopup: Bool {
        get { defaults.object(forKey: Key.dropletShowPopup) as? Bool ?? true } // default ON
        set { defaults.set(newValue, forKey: Key.dropletShowPopup) }
    }

    /// Whether exported droplets should play the finish chime by default.
    var dropletExportPlayChime: Bool {
        get { defaults.object(forKey: Key.dropletPlayChime) as? Bool ?? true } // default ON
        set { defaults.set(newValue, forKey: Key.dropletPlayChime) }
    }
}



// MARK: - Helpers

extension String {
    /// Treats "", "none", " None " etc. as unset.
    var isNoneOrEmpty: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lowercased() == "none"
    }

    /// Returns `self` unless it's "none"/empty, then returns the fallback.
    func or(_ fallback: String) -> String {
        isNoneOrEmpty ? fallback : self
    }
}
