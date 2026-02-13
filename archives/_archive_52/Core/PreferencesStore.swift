//
//  PreferencesStore.swift
//  MrHEVC
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
        return try decoder.decode(Settings.self, from: data)
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
                return try decoder.decode(Settings.self, from: data)
            }
        }
        throw StoreError.missingFactoryDefaults
    }

    func resetUserSettingsToFactoryDefaults() throws -> Settings {
        let defaults = try loadFactoryDefaults()
        try save(defaults)
        return defaults
    }

    private func userPrefsURL(createDirIfNeeded: Bool = false) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("MrHEVC", isDirectory: true)
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

    private final class BundleLocator {}
}
