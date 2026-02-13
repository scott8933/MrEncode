//
//  QueueImportResult.swift
//  MrEncode
//
//  Created by scott ulrich on 1/22/26.
//


import Foundation

// MARK: - QueueImportService

struct QueueImportResult {
    var candidates: [URL]          // top-level .mov/.qt files (deduped within batch)
    var warnings: [String]         // user-facing warning paragraphs
    var rejectedFilenames: [String]
    var sawSubfolders: [String]
    var sawAnyDirectory: Bool

    var requiresConfirm: Bool { candidates.count > 25 }
}

enum QueueImportService {

    /// Process picked URLs (files and/or directories). Directories are scanned
    /// *top-level only* for .mov/.qt. No recursive scan.
    static func process(_ urls: [URL]) -> QueueImportResult {
        let fm = FileManager.default

        let standardized = urls.map { $0.standardizedFileURL }

        var topLevelMovieFiles = Set<URL>()
        var rejected: [String] = []
        var sawSubfolders: [String] = []
        var warnings: [String] = []

        var sawAnyDirectory = false
        var sawAnyFile = false

        for url in standardized {
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            guard exists else { continue }

            if isDir.boolValue {
                sawAnyDirectory = true

                let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
                if let contents = try? fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    for child in contents {
                        if let rv = try? child.resourceValues(forKeys: Set(keys)) {
                            if rv.isDirectory == true {
                                sawSubfolders.append(child.lastPathComponent)
                            } else if rv.isRegularFile == true {
                                if isAllowedQuickTime(child) {
                                    topLevelMovieFiles.insert(child.standardizedFileURL)
                                }
                            }
                        }
                    }
                }
            } else {
                sawAnyFile = true
                if isAllowedQuickTime(url) {
                    topLevelMovieFiles.insert(url.standardizedFileURL)
                } else {
                    rejected.append(url.lastPathComponent)
                }
            }
        }

        // Warnings (mirrors existing UX language in UI_Queue)
        if !rejected.isEmpty {
            let fileList = rejected.count > 5
                ? Array(rejected.prefix(5)).joined(separator: ", ") + ", and \(rejected.count - 5) more"
                : rejected.joined(separator: ", ")
            warnings.append("Non-QuickTime files skipped: \(fileList)")
        }

        if !sawSubfolders.isEmpty {
            let folderList = sawSubfolders.count > 5
                ? Array(sawSubfolders.prefix(5)).joined(separator: ", ") + ", and \(sawSubfolders.count - 5) more"
                : sawSubfolders.joined(separator: ", ")
            warnings.append("Subfolders not scanned: \(folderList)")
        }

        // If user selected folders but there were no top-level movies, provide an explicit warning.
        // (This matches the “dropped folder(s)” UX you already built.)
        if topLevelMovieFiles.isEmpty && sawAnyDirectory && !sawAnyFile {
            warnings.append("No QuickTime (.mov) files found in the selected folder(s)")
        }

        // Allow duplicates in the queue (do not subtract existing items) — still dedupe within this batch.
        let candidates = Array(topLevelMovieFiles)

        return QueueImportResult(
            candidates: candidates,
            warnings: warnings,
            rejectedFilenames: rejected,
            sawSubfolders: sawSubfolders,
            sawAnyDirectory: sawAnyDirectory
        )
    }

    static func isAllowedQuickTime(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "mov" || ext == "qt"
    }
}
