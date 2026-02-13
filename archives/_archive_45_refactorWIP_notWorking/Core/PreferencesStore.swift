//
//  PreferencesSTore.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/1/25.
//

// =============================
// File: PreferencesStore.swift
// =============================
import Foundation


final class PreferencesStore {
private let filename = "prefs.json"


func load() throws -> Settings {
let url = try prefsURL()
let data = try Data(contentsOf: url)
let settings = try JSONDecoder().decode(Settings.self, from: data)
return settings
}


func save(_ settings: Settings) throws {
let url = try prefsURL(createDirIfNeeded: true)
let data = try JSONEncoder().encode(settings)
try data.write(to: url, options: [.atomic])
}


// ~/Library/Application Support/MrHEVC/prefs.json
private func prefsURL(createDirIfNeeded: Bool = false) throws -> URL {
let fm = FileManager.default
let appSup = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
let dir = appSup.appendingPathComponent("MrHEVC", isDirectory: true)
if createDirIfNeeded && !fm.fileExists(atPath: dir.path) {
try fm.createDirectory(at: dir, withIntermediateDirectories: true)
}
return dir.appendingPathComponent(filename)
}
}
