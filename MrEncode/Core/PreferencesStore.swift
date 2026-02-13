//
//  PreferencesStore.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/1/25.
//

// =============================
// File: PreferencesStore.swift
// =============================
import Foundation

final class PreferencesStore {
    enum StoreError: Swift.Error {
        case missingFactoryDefaults
    }

    private let userFilename = "prefs.json"
    private let factoryResourceName = "default_prefs"
    private let factoryResourceExtension = "json"

    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    func loadUserSettings() throws -> Settings {
        let url = try userPrefsURL()
        let data = try Data(contentsOf: url)
        return try decodeSettingsMergingFactoryDefaults(from: data)
    }


    func save(_ settings: Settings) throws {
        let url = try userPrefsURL(createDirIfNeeded: true)
        let data = try encoder.encode(settings)
        try data.write(to: url, options: [.atomic])
    }

    func userPrefsExist() -> Bool {
        guard let url = try? userPrefsURL() else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    func bootstrapUserPrefsIfNeeded() throws -> Settings {
        if userPrefsExist() {
            return try loadUserSettings()
        }

        let defaults = try loadFactoryDefaults()
        try save(defaults)
        return defaults
    }

    func loadFactoryDefaults() throws -> Settings {
        for bundle in factoryBundles() {
            if let url = bundle.url(forResource: factoryResourceName, withExtension: factoryResourceExtension) {
                let data = try Data(contentsOf: url)
                return try decodeSettingsMergingFactoryDefaults(from: data)
            }
        }
        throw StoreError.missingFactoryDefaults
    }

    func resetUserSettingsToFactoryDefaults() throws -> Settings {
        let defaults = try loadFactoryDefaults()
        try save(defaults)
        return defaults
    }
    
    
    
    // MARK: - Corrupt prefs quarantine (self-healing)

    /// Moves the current prefs.json aside (timestamped) so we can regenerate clean prefs.
    /// Returns the quarantined URL if a file was moved.
    @discardableResult
    func quarantineUserPrefsFile(prefix: String = "prefs_corrupt") -> URL? {
        do {
            // Ensure directory exists
            let src = try userPrefsURL(createDirIfNeeded: true)
            guard fileManager.fileExists(atPath: src.path) else { return nil }

            let iso = ISO8601DateFormatter()
            var ts = iso.string(from: Date())
            ts = ts.replacingOccurrences(of: ":", with: "-") // safe for filenames

            let dst = src.deletingLastPathComponent()
                .appendingPathComponent("\(prefix)_\(ts).json")

            do {
                try fileManager.moveItem(at: src, to: dst)
                return dst
            } catch {
                // If move fails (rare), try copy+remove.
                do {
                    try fileManager.copyItem(at: src, to: dst)
                    try fileManager.removeItem(at: src)
                    return dst
                } catch {
                    return nil
                }
            }
        } catch {
            return nil
        }
    }

    
    private func userPrefsURL(createDirIfNeeded: Bool = false) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("MrEncode", isDirectory: true)
        if createDirIfNeeded && !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(userFilename)
    }

    private func factoryBundles() -> [Bundle] {
        var bundles: [Bundle] = []
        bundles.append(Bundle.main)

        let locatorBundle = Bundle(for: BundleLocator.self)
        if locatorBundle.bundleURL != Bundle.main.bundleURL {
            bundles.append(locatorBundle)
        }
        return bundles
    }
    
    // MARK: - Defaults-merge decoding (schema-safe)

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
        // Arrays: overlay wins wholesale (predictable behavior)
        if let o = overlay as? [Any] {
            return o
        }
        return overlay
    }

    private func loadFactoryDefaultsDictionary() throws -> [String: Any] {
        for bundle in factoryBundles() {
            if let url = bundle.url(forResource: factoryResourceName,
                                    withExtension: factoryResourceExtension) {
                let data = try Data(contentsOf: url)
                let obj = try JSONSerialization.jsonObject(with: data, options: [])
                guard let dict = obj as? [String: Any] else {
                    throw StoreError.missingFactoryDefaults
                }
                return dict
            }
        }
        throw StoreError.missingFactoryDefaults
    }

    private func decodeSettingsMergingFactoryDefaults(from overlayData: Data) throws -> Settings {
        let factoryDict = try loadFactoryDefaultsDictionary()

        let overlayObj = try JSONSerialization.jsonObject(with: overlayData, options: [])
        guard let overlayDict = overlayObj as? [String: Any] else {
            throw StoreError.missingFactoryDefaults
        }

        let merged = deepMerge(factoryDict, overlayDict)
        let mergedData = try JSONSerialization.data(withJSONObject: merged, options: [])
        return try decoder.decode(Settings.self, from: mergedData)
    }


    private final class BundleLocator {}
}
