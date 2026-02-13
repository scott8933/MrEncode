//
//  QueueFileDocument.swift
//  MrEncode
//
//  Created by scott ulrich on 1/22/26.
//


import SwiftUI
import UniformTypeIdentifiers

// MARK: - UTType

extension UTType {
    static let mrqQueue: UTType = UTType(exportedAs: "com.grayrobot.mrencode.queue")
}

// MARK: - FileDocument

/// SwiftUI document wrapper used by .fileExporter / .fileImporter.
///
/// Save-only for now; Open will come next (init(configuration:) + read).
struct QueueFileDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.mrqQueue] }

    var document: QueueDocument

    init(document: QueueDocument) {
        self.document = document
    }

    /// Required by FileDocument even if you don’t support Open yet.
    /// We will implement this for Open next.
    init(configuration: ReadConfiguration) throws {
        // For now, we can either:
        // 1) Throw (disables import usage) or
        // 2) Implement decoding now (recommended, even if UI import comes later).
        //
        // I recommend implementing now because it’s small and future-proofs immediately.

        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(QueueDocument.self, from: data)

        // Basic type guard for safety:
        guard decoded.format == QueueDocument.formatID else {
            throw QueueSaveError.invalidDocumentFormat(decoded.format)
        }

        self.document = decoded
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(document)
            return FileWrapper(regularFileWithContents: data)
        } catch {
            throw QueueSaveError.failedToEncode(error)
        }
    }
}
