//
//  QueueSaveError.swift
//  MrEncode
//
//  Created by scott ulrich on 1/22/26.
//


import Foundation

enum QueueSaveError: LocalizedError {
    case invalidDocumentFormat(String)
    case failedToEncode(Error)
    case failedToWrite(Error)

    var errorDescription: String? {
        switch self {
        case .invalidDocumentFormat(let f):
            return "Invalid queue document format: \(f)"
        case .failedToEncode(let e):
            return "Failed to encode queue JSON: \(e.localizedDescription)"
        case .failedToWrite(let e):
            return "Failed to write queue file: \(e.localizedDescription)"
        }
    }
}

/// Responsible for producing and saving QueueDocument JSON.
struct QueueSaveService {

    /// Builds a QueueDocument from runtime items.
    /// IMPORTANT: This is the choke-point where you decide what belongs in the saved queue.
    static func makeDocument(
        items: [MediaItem],
        appName: String = "MrEncode",
        build: String? = nil,
        platform: String? = "macOS"
    ) -> QueueDocument {

        let docItems = items.map { $0.toQueueDocumentItem() }

        return QueueDocument(
            app: QueueDocumentAppInfo(name: appName, build: build, platform: platform),
            createdAt: Date(),
            items: docItems
        )
    }

    /// Saves document to disk as pretty JSON, atomically.
    static func save(document: QueueDocument, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw QueueSaveError.failedToEncode(error)
        }

        do {
            // Atomic write prevents partial/corrupt saves.
            try data.write(to: url, options: [.atomic])
        } catch {
            throw QueueSaveError.failedToWrite(error)
        }
    }
}

