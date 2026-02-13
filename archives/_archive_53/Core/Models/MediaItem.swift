//
//  EncodeStatus.swift
//  MrEncode
//
//  Created by scott ulrich on 1/22/26.
//


//
//  MediaItem.swift
//

import Foundation
import AVFoundation

// MARK: - Encode status

enum EncodeStatus: String, Codable {
    case queued
    case encoding
    case done
    case error
    case blocked
}

// MARK: - Progress mode

enum ProgressMode: String, Codable {
    case none
    case real   // from media time
    case fake   // from wall-time estimate
}

// MARK: - Media metadata (subset used by pipeline)

struct MediaMetadata: Codable, Equatable {
    // Duration & rate
    var durationSeconds: Double = 0
    var nominalFPS: Double? = nil

    // Timecode
    var startTimecode: String? = nil

    // NCLC tags (pass-through when user chooses "No Change")
    var colorPrimaries: String? = nil
    var transferFunction: String? = nil
    var ycbcrMatrix: String? = nil

    static let empty = MediaMetadata()

    /// Merge non-nil values from `other` into `self`.
    mutating func coalesce(with other: MediaMetadata) {
        if durationSeconds <= 0, other.durationSeconds > 0 { durationSeconds = other.durationSeconds }
        if nominalFPS == nil, let v = other.nominalFPS { nominalFPS = v }
        if startTimecode == nil, let v = other.startTimecode { startTimecode = v }
        if colorPrimaries == nil, let v = other.colorPrimaries { colorPrimaries = v }
        if transferFunction == nil, let v = other.transferFunction { transferFunction = v }
        if ycbcrMatrix == nil, let v = other.ycbcrMatrix { ycbcrMatrix = v }
    }
}

// MARK: - Media item

struct MediaItem: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var meta: MediaMetadata
    var isChecked: Bool = false

    // Encode bookkeeping
    var status: EncodeStatus = .queued
    var statusReason: String? = nil

    // Non-blocking warning message shown in expanded details
    var warningReason: String? = nil

    // Destination planning
    var plannedOutputURL: URL? = nil
    var finalOutputURL: URL? = nil
    var allowOverwrite: Bool = false

    var tempOutputURL: URL?
    var actualEncodeSeconds: TimeInterval? = nil

    // Progress UI
    var progressMode: ProgressMode = .none
    var progress: Double? = nil
    var etaSeconds: Double? = nil

    // Output info
    var outputSizeBytes: Int64? = nil
    var logURL: URL? = nil

    // Metadata pass
    var isProcessingMetadata: Bool = false
    var metadataProgress: Double? = nil

    // Caching
    private var _cachedSrcLine: String?
    private var _cachedDstLine: String?
    private var _cachedFileSize: Int64?

    mutating func setCachedSrcLine(_ line: String) { _cachedSrcLine = line }
    mutating func setCachedDstLine(_ line: String) { _cachedDstLine = line }
    mutating func setCachedFileSize(_ size: Int64) { _cachedFileSize = size }

    var cachedSrcLine: String? { _cachedSrcLine }
    var cachedDstLine: String? { _cachedDstLine }
    var cachedFileSize: Int64? { _cachedFileSize }

    init(
        url: URL,
        meta: MediaMetadata,
        status: EncodeStatus = .queued,
        statusReason: String? = nil
    ) {
        self.url = url
        self.meta = meta
        self.status = status
        self.statusReason = statusReason
        self.isChecked = (status != .blocked)
    }
}


extension MediaItem {

    /// If MediaItem already has a stable id, use it.
    /// If not, add `let id: UUID` to MediaItem and set on creation.
    fileprivate var persistentID: UUID {
        // Replace with your real id field if present:
        if let existing = (Mirror(reflecting: self).children.first { $0.label == "id" }?.value as? UUID) {
            return existing
        }
        // Fallback: DO NOT keep this long-term; add a real id to MediaItem.
        return UUID()
    }

    func toQueueDocumentItem() -> QueueDocumentItem {
        // Source
        let sourceURLString = url.absoluteString

        // Optional bookmark: only if you already have one.
        // If you store bookmark data somewhere, encode as base64 here.
        let bookmarkBase64: String? = nil // ← wire later if you have bookmark Data

        // Plan (adapt to your app)
        // I’m assuming you have settings/codec/container concept somewhere per job.
        // If per-item overrides don’t exist yet, it’s OK to record nils.
        let plan = QueueDocumentPlan(
            codec: extractCodecStringIfAvailable(),
            container: extractContainerStringIfAvailable(),
            destination: extractDestinationURLIfAvailable().map { QueueDocumentDestination(url: $0.absoluteString) },
            flags: QueueDocumentPlanFlags(remoteDeadline: extractRemoteDeadlineFlagIfAvailable()),
            cliArgs: nil
        )

        // Extensions (future AE/Nuke hooks). If you have none yet, omit.
        let extPayload: [String: JSONValue]? = nil

        return QueueDocumentItem(
            id: persistentID,
            addedAt: Date(), // or the item’s original enqueue time if you track it
            source: QueueDocumentSource(url: sourceURLString, bookmark: bookmarkBase64),
            plan: plan,

            // NEW: persist queue-row state
            queue: QueueDocumentQueueState(
                isChecked: self.isChecked,
                status: self.status.rawValue,
                statusReason: self.statusReason
            ),

            extensions: extPayload,
            notes: nil
        )
    }

    // MARK: - Adaptation hooks (replace with your real fields)

    private func extractCodecStringIfAvailable() -> String? {
        // Example only:
        // return meta.codecName
        // return settings.codec.rawValue
        return nil
    }

    private func extractContainerStringIfAvailable() -> String? {
        // Example only:
        // return settings.container.rawValue
        return nil
    }

    private func extractDestinationURLIfAvailable() -> URL? {
        // Example only:
        // return meta.outputURL
        // return settings.outputURL(for: self)
        return nil
    }

    private func extractRemoteDeadlineFlagIfAvailable() -> Bool? {
        // Example only:
        // return (settings.runMode == .remoteDeadline)
        return nil
    }
}
