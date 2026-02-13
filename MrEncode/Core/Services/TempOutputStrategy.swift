//
//  TempOutputStrategy.swift
//  MrEncode
//
//  Created by scott ulrich on 2/5/26.
//


import Foundation

enum TempOutputStrategy {

    // MARK: - Public

    static func makeTempURL(for finalURL: URL) throws -> URL {
        let fm = FileManager.default
        let destDir = finalURL.deletingLastPathComponent()

        let baseName = finalURL.lastPathComponent
        let tempName = ".tmp-\(UUID().uuidString)-\(baseName)"

        // If dest is in a coordinated/“unsafe” location, force temp into system temp.
        if isUnsafeCoordinatedDestinationDirectory(destDir) {
            let root = try mrencodeTempRoot()
            try ensureDir(root)

            let tempURL = root.appendingPathComponent(tempName, isDirectory: false)
            return tempURL
        }

        // Otherwise prefer same-directory sibling hidden temp folder (fast rename path, minimal overhead).
        let siblingTmpDir = destDir.appendingPathComponent(".mrencode_tmp", isDirectory: true)
        try ensureDir(siblingTmpDir)

        let tempURL = siblingTmpDir.appendingPathComponent(tempName, isDirectory: false)
        return tempURL
    }

    // MARK: - Unsafe / coordinated folder detection

    /// Conservative rule: treat Desktop, Documents, iCloud Drive (and CloudDocs) as unsafe.
    /// This is specifically to avoid .sb-* artifacts caused by coordination/safe-save behaviors.
    static func isUnsafeCoordinatedDestinationDirectory(_ dir: URL) -> Bool {
        // Standard user folders (these are common coordination hotspots)
        let unsafeStandardDirs: [FileManager.SearchPathDirectory] = [
            .desktopDirectory,
            .documentDirectory
        ]

        for spd in unsafeStandardDirs {
            if let std = FileManager.default.urls(for: spd, in: .userDomainMask).first,
               isSameOrDescendant(dir, of: std) {
                return true
            }
        }

        // iCloud Drive root is not always returned consistently via SearchPathDirectory, so also detect by path.
        // Typical paths:
        // - ~/Library/Mobile Documents/com~apple~CloudDocs/...
        // - /Users/<u>/Library/Mobile Documents/...
        let p = dir.standardizedFileURL.path
        if p.contains("/Library/Mobile Documents/") { return true }
        if p.contains("com~apple~CloudDocs") { return true }

        // If the directory itself is marked ubiquitous, treat as unsafe.
        // (Can be nil/false for some providers, but harmless as an extra signal.)
        if let vals = try? dir.resourceValues(forKeys: [.isUbiquitousItemKey]),
           vals.isUbiquitousItem == true {
            return true
        }

        return false
    }

    // MARK: - Helpers

    private static func mrencodeTempRoot() throws -> URL {
        let fm = FileManager.default
        let base = fm.temporaryDirectory
        // Keep it stable and easy to sweep.
        return base
            .appendingPathComponent("MrEncode", isDirectory: true)
            .appendingPathComponent("Encodes", isDirectory: true)
    }

    private static func ensureDir(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    private static func isSameOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let c = candidate.standardizedFileURL.path
        let a = ancestor.standardizedFileURL.path
        return c == a || c.hasPrefix(a.hasSuffix("/") ? a : (a + "/"))
    }
}
