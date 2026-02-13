//
//  QueueDocument.swift
//  MrEncode
//
//  Created by scott ulrich on 1/22/26.
//


import Foundation

// MARK: - Queue Document (Persisted JSON)

// Top-level file
struct QueueDocument: Codable {
    static let formatID = "mrencode.queue"
    static let currentVersion = 2

    var format: String = QueueDocument.formatID
    var version: Int = QueueDocument.currentVersion

    var app: QueueDocumentAppInfo?
    var createdAt: Date
    var items: [QueueDocumentItem]
}

// Optional app info: safe to include; not a "preset".
struct QueueDocumentAppInfo: Codable {
    var name: String
    var build: String?
    var platform: String?
}


struct QueueDocumentItem: Codable {
    var id: UUID
    var addedAt: Date?

    var source: QueueDocumentSource
    var plan: QueueDocumentPlan

    // NEW (optional so older files still load)
    var queue: QueueDocumentQueueState?

    // Future-proof extension hook payloads (AE, Nuke, etc.)
    var extensions: [String: JSONValue]?

    var notes: String?
}



// MARK: - Persisted queue-row state (runtime-only, not presets)

struct QueueDocumentQueueState: Codable {
    /// Mirrors MediaItem.isChecked
    var isChecked: Bool

    /// EncodeStatus.rawValue ("queued", "blocked", etc.)
    var status: String?

    /// Human-readable reason (e.g. "blocked: source file missing")
    var statusReason: String?
}


struct QueueDocumentSource: Codable {
    /// File URL as string to preserve exactness and remain CLI-friendly.
    var url: String

    /// Optional base64-encoded security-scoped bookmark for future robust re-open access.
    /// (You can write it now even if you don’t consume it yet.)
    var bookmark: String?
}

struct QueueDocumentPlan: Codable {
    // Keep this minimal and stable. Add fields over time (all optional when possible).
    var codec: String?
    var container: String?

    var destination: QueueDocumentDestination?

    // Example: carry a minimal run-mode hint per item (not global settings/presets).
    var flags: QueueDocumentPlanFlags?

    // Optional pass-through args for future CLI parity (do not rely on it yet).
    var cliArgs: [String]?
}

struct QueueDocumentDestination: Codable {
    var url: String
}

struct QueueDocumentPlanFlags: Codable {
    var remoteDeadline: Bool?
}

// MARK: - Arbitrary JSON Value (for extensions)

enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()

        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }

        throw DecodingError.typeMismatch(
            JSONValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}
