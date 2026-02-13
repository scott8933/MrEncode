//
//  PreflightService.swift
//  MrEncode
//
//  Created by scott ulrich on 1/25/26.
//



// PreflightService.swift
import Foundation

final class PreflightService {
    static let shared = PreflightService()

    enum IssueLevel {
        case warning
        case error
    }

    struct Issue {
        let id: UUID
        let level: IssueLevel
        let message: String
        let detail: String?
        let sourceURL: URL?
        let destinationURL: URL?
    }

    private init() {}

    func preflightSelected(
        files: inout [MediaItem],
        selectedIDs: Set<UUID>,
        settings: Settings
    ) -> [Issue] {
        var issues: [Issue] = []
        var plannedDestinations: [URL: UUID] = [:]

        for idx in files.indices {
            guard selectedIDs.contains(files[idx].id) else { continue }
            if files[idx].status == .encoding { continue }

            if !sourceExistsAndIsFile(files[idx].url) {
                block(&files[idx], reason: "Source is missing.")
                issues.append(Issue(
                    id: files[idx].id,
                    level: .error,
                    message: "Blocked: Source is missing.",
                    detail: files[idx].url.path,
                    sourceURL: files[idx].url,
                    destinationURL: files[idx].plannedOutputURL
                ))
                continue
            }

            guard let dest = files[idx].plannedOutputURL else {
                block(&files[idx], reason: "Destination is not set.")
                issues.append(Issue(
                    id: files[idx].id,
                    level: .error,
                    message: "Blocked: Destination is not set.",
                    detail: nil,
                    sourceURL: files[idx].url,
                    destinationURL: nil
                ))
                continue
            }


            let parent = dest.deletingLastPathComponent()
            if !ensureDirectoryExists(parent) {
                block(&files[idx], reason: "Destination directory is not writable.")
                issues.append(Issue(
                    id: files[idx].id,
                    level: .error,
                    message: "Blocked: Destination directory is not writable.",
                    detail: parent.path,
                    sourceURL: files[idx].url,
                    destinationURL: dest
                ))
                continue
            }

            if FileManager.default.fileExists(atPath: dest.path),
               files[idx].allowOverwrite == false {
                block(&files[idx], reason: "Destination exists.")
                issues.append(Issue(
                    id: files[idx].id,
                    level: .error,
                    message: "Blocked: Destination exists (overwrite disabled).",
                    detail: dest.path,
                    sourceURL: files[idx].url,
                    destinationURL: dest
                ))
                continue
            }

            if let otherID = plannedDestinations[dest], otherID != files[idx].id {
                block(&files[idx], reason: "Destination conflicts with another queued item.")
                issues.append(Issue(
                    id: files[idx].id,
                    level: .error,
                    message: "Blocked: Destination conflicts with another queued item.",
                    detail: dest.path,
                    sourceURL: files[idx].url,
                    destinationURL: dest
                ))
                continue
            }

            plannedDestinations[dest] = files[idx].id
        }

        for idx in files.indices where files[idx].status == .blocked {
            files[idx].isChecked = false
        }

        return issues
    }

    private func block(_ item: inout MediaItem, reason: String) {
        item.status = .blocked
        item.statusReason = reason
        item.isChecked = false
    }

    private func sourceExistsAndIsFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && !isDir.boolValue
    }

    private func ensureDirectoryExists(_ url: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return true }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}

