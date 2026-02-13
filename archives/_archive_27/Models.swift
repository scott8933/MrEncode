// =============================
// File: Models.swift
// =============================

import Foundation
import AVFoundation

// MARK: - Run Mode

enum RunMode: String, CaseIterable, Codable, Identifiable {
    case localFFmpeg     = "Local"
    case remoteDeadline  = "Remote (Deadline)"

    var id: String { rawValue }
}

// MARK: - Scale

enum ScaleOption: String, CaseIterable, Codable, Identifiable {
    case oneToOne = "1:1 (No Scale)"
    case half     = "1/2"
    case quarter  = "1/4"

    var id: String { rawValue }

    /// Numeric scale factor used by rendering / sanity checks.
    var factor: Double {
        switch self {
        case .oneToOne: return 1.0
        case .half:     return 0.5
        case .quarter:  return 0.25
        }
    }
}

// MARK: - Burn-in positions

enum BurnInPosition: String, CaseIterable, Codable, Identifiable {
    case upperLeft
    case upperCenter
    case upperRight
    case middleLeft
    case middleRight
    case lowerLeft
    case lowerCenter
    case lowerRight

    var id: String { rawValue }
}

// MARK: - Progress mode

enum ProgressMode: String, Codable {
    case none
    case real   // from media time
    case fake   // from wall-time estimate
}

// MARK: - Encode status

enum EncodeStatus: String, Codable {
    case queued
    case encoding
    case done
    case error
    case blocked
}

// MARK: - Messaging

enum LogLevel: String, Codable {
    case info
    case warning
    case error
}

struct AppLogEntry: Identifiable, Codable {
    let id = UUID()
    let date: Date
    let level: LogLevel
    let message: String
    let filename: String?
    var code: LogCode? = nil
    var originKey: String? = nil     // freeform (e.g. "farm-path", "deadline-submit")
    var acknowledged: Bool = false   // dim once the condition is resolved
    let logURL: URL?
}

// MARK: - Media metadata (subset used by pipeline)

struct MediaMetadata: Codable, Equatable {
    // Duration & rate
    var durationSeconds: Double = 0
    var nominalFPS: Double? = nil

    // Timecode
    var startTimecode: String? = nil

    // NCLC tags (pass-through when user chooses “No Change”)
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
    let url: URL
    var meta: MediaMetadata
    var isChecked: Bool = false

    // Encode bookkeeping
    var status: EncodeStatus = .queued
    var statusReason: String? = nil

    var finalOutputURL: URL? = nil
    var actualEncodeSeconds: TimeInterval? = nil

    // Progress UI
    var progressMode: ProgressMode = .none
    var progress: Double? = nil            // 0..1
    var etaSeconds: Double? = nil

    // Optional: track output size for any size model you maintain
    var outputSizeBytes: Int64? = nil
    
    var logURL: URL? = nil   // path to per-item ffmpeg log (if any)

}

// Orderable pieces for filename assembly
enum FilenamePart: String, Codable, CaseIterable, Identifiable {
    case nclc, scale, compression
    var id: String { rawValue }
    var label: String {
        switch self {
        case .nclc:        return "NCLC"
        case .scale:       return "Scale"
        case .compression: return "Compression"
        }
    }
}

// Error codes for log
enum LogCode: String, Codable {
    case farmPath           // remote path not accessible to farm
    case noOp               // "Nothing to do!"
    case wouldOverwrite     // output name would match source
    case other              // everything else (no auto-ack)
}

// MARK: - Settings

struct Settings: Codable {
    
    // MARK: Run mode
    var runMode: RunMode = .remoteDeadline

    // MARK: Panel state
    var generalExpanded: Bool  = true     // "Compression"
    var nclcExpanded: Bool     = true     // "NCLC Settings"
    var overlaysExpanded: Bool = true     // "Overlays"
    var deadlineExpanded: Bool = true     // "Deadline Options"
    var scaleExpanded: Bool    = true     // "Scale & Crop"

    // MARK: Compression & Resizing
    var bypassHEVC: Bool = false
    var qualityCRF: Int = 18
    var outputSuffix: String = "-HEVC"
    
    // MARK: Scale & Crop
    var scale: ScaleOption = .oneToOne
    var scaleSuffix: String = ""   // blank when .oneToOne

    // MARK: NCLC Settings
    var nclcTag: String = Self.nclcOptionOrderTopFirst.first ?? "No Change"
    var nclcFilenameLabel: String = ""

    // MARK: Auto-Encode (alias for legacy turboMode)
    var autoEncodeOnDrop: Bool = false

    // MARK: Burn-ins
    var burnInFrames: Bool = false
    var burnInTimecode: Bool = false
    var burnInFilename: Bool = false

    var burnInFramesPosition: BurnInPosition   = .upperLeft
    var burnInTimecodePosition: BurnInPosition = .lowerLeft
    var burnInFilenamePosition: BurnInPosition = .lowerRight

    // MARK: Overlay appearance
    var overlayTextColorHex: String = "#FFFFFF"
    var overlayTextColorAlpha: Double = 1.0
    var overlayBoxEnabled: Bool = true
    var overlayBoxColorHex: String = "#000000"
    var overlayBoxColorAlpha: Double = 0.80

    // MARK: Metadata cache (optional)
    var meta: MediaMetadata = .empty

    // MARK: Deadline
    var deadlineCommandPath: String = ""   // auto-detected if empty
    var priority: Int = 50                 // 0..100
    var pool: String = ""
    var secondaryPool: String = ""
    var group: String = ""
    var batchName: String = ""
    var jobName: String = ""
    var comment: String = ""
    var dependencies: String = ""
    /// Security-scoped bookmark for ~/Library/Application Support/Thinkbox/Deadline10
    var deadlineUserHomeBookmark: Data? = nil

    /// Populated by Deadline refresh; persisted for next run.
    var poolOptions: [String] = [] {
        didSet {
            if let first = poolOptions.first {
                if pool.isEmpty || !poolOptions.contains(pool) { pool = first }
                if secondaryPool.isEmpty || !poolOptions.contains(secondaryPool) { secondaryPool = first }
            } else {
                pool = ""
                secondaryPool = ""
            }
        }
    }
    var groupOptions: [String] = [] {
        didSet {
            // Default to top option if current selection missing
            if let first = groupOptions.first, (group.isEmpty || !groupOptions.contains(group)) {
                group = first
            }
        }
    }

    /// Refresh timestamp (so UI can know if lists are stale)
    var lastDeadlineFetch: Date? = nil
    
    // MARK: Preferences
    var filenameOrder: [FilenamePart] = [.nclc, .scale, .compression]
}

// MARK: - Sanity helpers - (prevent source overwrites)

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
}

extension Settings {
    /// Compression panel considered "inactive" when bypass + 1:1 + no filename suffix.
    var isCompressionPanelInactive: Bool {
        bypassHEVC && scale == .oneToOne && outputSuffix.trimmed.isEmpty
    }

    /// NCLC panel considered "inactive" when dropdown says No Change and label is empty.
    var isNclcPanelInactive: Bool {
        nclcTag.trimmed.lowercased() == "no change" && nclcFilenameLabel.trimmed.isEmpty
    }

    /// Overlays panel inactive when nothing is toggled on.
    var isOverlaysPanelInactive: Bool {
        !(burnInFrames || burnInTimecode || burnInFilename)
    }

    /// All panels together would do nothing.
    var isEverythingInactive: Bool {
        isCompressionPanelInactive && isNclcPanelInactive && isOverlaysPanelInactive
    }

    /// Both filename-affecting suffixes are blank → output name equals input base name.
    var bothSuffixesBlank: Bool {
        outputSuffix.trimmed.isEmpty && nclcFilenameLabel.trimmed.isEmpty
    }
}


// MARK: - Settings dropdown helpers

extension Settings {
    /// Single source of truth for NCLC option order (top-first).
    static let nclcOptionOrderTopFirst: [String] = [
        "No Change",
        "1-1-1 (BT.709)",
        "1-13-1 (sRGB)",
        "12-16-1 (P3-D65)",
        "12-13-1 (DisplayP3)",
        "9-16-9 (BT.2020)",
        "9-18-9 (BT.2020 HLG)",
        "9-16-10 (BT.2020 PQ CL)",
        "6-6-6 (Rec.601 NTSC)",
        "5-6-5 (Rec.601 PAL)",
        "9-1-9 (BT.2020 SDR)",
        "9-14-9 (BT.2020 SDR BT.1361)",
        "1-4-1 (BT.709 γ2.2)",
        "1-5-1 (BT.709 γ2.8)"
    ]

    /// Call this after loading preferences, and again after pool/group lists are fetched.
    mutating func coerceDropdownDefaultsTopFirst() {
        // NCLC Tagging
        if !Self.nclcOptionOrderTopFirst.contains(nclcTag) {
            nclcTag = Self.nclcOptionOrderTopFirst.first ?? "No Change"
        }
        // Pools / Groups (if lists are present)
        if let firstPool = poolOptions.first {
            if pool.isEmpty || !poolOptions.contains(pool) { pool = firstPool }
            if secondaryPool.isEmpty || !poolOptions.contains(secondaryPool) { secondaryPool = firstPool }
        }
        if let firstGroup = groupOptions.first, (group.isEmpty || !groupOptions.contains(group)) {
            group = firstGroup
        }
        // Enums: ensure valid if ever corrupted
        if let topRun = RunMode.allCases.first, !RunMode.allCases.contains(runMode) { runMode = topRun }
        if let topScale = ScaleOption.allCases.first, !ScaleOption.allCases.contains(scale) { scale = topScale }
    }
}
