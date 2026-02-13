// =============================
// File: Models.swift
// =============================
import Foundation
import AVFoundation

enum MediaStatus: String, Codable, Hashable { // ← added Hashable
    case queued
    case encoding
    case done
    case error
    case blocked   // not farm-accessible (e.g., Desktop/Downloads/local home)
}

// MARK: - Transient encode progress (UI-only, not persisted)
enum ProgressMode: Hashable { // ← added Hashable
    case none      // hidden
    case real      // parsed from ffmpeg time=
    case fake      // elapsed / estimate
}

struct MediaItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var status: MediaStatus = .queued
    var statusReason: String? = nil  // short explanation for blocked/error
    var meta: MediaMetadata = .empty
    var finalOutputURL: URL? = nil
    var actualEncodeSeconds: Double? // actual encoding time for stats display
    
    // Progress: 0...1 (nil = indeterminate)
    var progress: Double? = nil
    var progressMode: ProgressMode = .none

    // Optional ETA (seconds) for display; not required
    var etaSeconds: Double? = nil

}

enum RunMode: String, Codable, CaseIterable, Identifiable {
    case localFFmpeg   = "Local"
    case remoteDeadline = "Renderfarm"
    var id: String { rawValue }
}

enum BurnInPosition: String, Codable, CaseIterable, Identifiable {
    case upperLeft, upperCenter, upperRight
    case middleLeft,       /* center */      middleRight
    case lowerLeft, lowerCenter, lowerRight
    var id: String { rawValue }

    /// Only allow corners + edge centers
    static let allowed: [BurnInPosition] = [
        .upperLeft, .upperCenter, .upperRight,
        .middleLeft,               .middleRight,
        .lowerLeft, .lowerCenter, .lowerRight
    ]
}

// MARK: - App Log

enum LogLevel: String, Codable, CaseIterable {
    case info, warning, error
}

struct AppLogEntry: Identifiable, Codable, Equatable {
    let id = UUID()
    let date: Date
    let level: LogLevel
    let message: String
    let filename: String?
}


// MARK: - Scale Options (standardized case names)
enum ScaleOption: String, Codable, CaseIterable, Identifiable {
    case oneToOne = "1:1 (No Scale)"
    case half     = "1/2 Size"
    case quarter  = "1/4 Size"

    var id: String { rawValue }

    var factor: Double {
        switch self {
        case .oneToOne: return 1.0
        case .half:     return 0.5
        case .quarter:  return 0.25
        }
    }
}

// imports/models

struct Settings: Codable {
    // Common
    var runMode: RunMode = .remoteDeadline
    var qualityCRF: Int = 18
    var scale: ScaleOption = .oneToOne
    var nclcTag: String = "no change"
    var outputSuffix: String = "-HEVC"
    
    // Auto Encoding
    // Alias out old var of "turboMode"
    var turboMode: Bool = false
    var autoEncodeOnDrop: Bool {
        get { turboMode }
        set { turboMode = newValue }
    }
    
    var mainExpanded: Bool = true
    
    // Advanced panel state + burn-ins
    var advancedExpanded: Bool = false
    var burnInFrames: Bool = false
    var burnInTimecode: Bool = false
    var burnInFilename: Bool = false
    
    // For querying QT data
    var meta: MediaMetadata = .empty
    
    // Default burn-in positions
    var burnInFramesPosition: BurnInPosition = .upperLeft
    var burnInTimecodePosition: BurnInPosition = .lowerLeft
    var burnInFilenamePosition: BurnInPosition = .lowerRight
    
    // Overlay appearance (global for all burn-ins)
    var overlayTextColorHex: String = "#FFFFFF"
    var overlayTextColorAlpha: Double = 1.0

    var overlayBoxEnabled: Bool = true
    var overlayBoxColorHex: String = "#000000"
    var overlayBoxColorAlpha: Double = 0.80

    // Deadline
    var deadlineExpanded: Bool = true
    var deadlineCommandPath: String = ""   // auto-detected if empty
    var priority: Int = 50                 // 0..100
    var pool: String = ""
    var secondaryPool: String = ""
    var group: String = ""
    var batchName: String = ""
    var jobName: String = ""
    var comment: String = ""
    var dependencies: String = ""
    var deadlineUserHomeBookmark: Data? = nil // security-scoped bookmark for ~/Library/Application Support/Thinkbox/Deadline10

    // Populated from DeadlineService; persisted for next run
    var poolOptions: [String] = []
    var groupOptions: [String] = []

    // Update Deadline settings after we launch + populate UI in case DL is slow to respond
    var lastDeadlineFetch: Date? = nil
}


// Merge helper: fill only the nil fields from `other`.
extension MediaMetadata {
    mutating func coalesce(with other: MediaMetadata) {
        if startTimecode == nil { startTimecode = other.startTimecode }
        if nominalFPS   == nil { nominalFPS   = other.nominalFPS }
        if colorPrimaries == nil { colorPrimaries = other.colorPrimaries }
        if transferFunction == nil { transferFunction = other.transferFunction }
        if ycbcrMatrix == nil { ycbcrMatrix = other.ycbcrMatrix }
    }
}


// Per-file technical metadata we extract on drop
struct MediaMetadata: Codable, Hashable {
    // NCLC
    var colorPrimaries: String?      // e.g. "bt709"
    var transferFunction: String?    // e.g. "bt709" / "smpte2084"
    var ycbcrMatrix: String?         // e.g. "bt709" / "bt2020nc"

    // Timebase / timecode
    var nominalFPS: Double?          // from video track
    var hasTimecodeTrack: Bool       // true if a tmcd track exists
    var startTimecode: String?       // "HH:MM:SS:FF" or "HH:MM:SS;FF"
    var durationSeconds: Double?     // total duration in seconds

    static let empty = MediaMetadata(
        colorPrimaries: nil, transferFunction: nil, ycbcrMatrix: nil,
        nominalFPS: nil, hasTimecodeTrack: false, startTimecode: nil,
        durationSeconds: nil
    )
}
