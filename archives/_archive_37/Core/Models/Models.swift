// =============================
// File: Models.swift - Complete Revised with Preset Support
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
    var originKey: String? = nil
    var acknowledged: Bool = false
    let logURL: URL?
    var detail: String? = nil     // long stderr / Deadline excerpt
    var jobID: String? = nil      // Deadline job id (when available)
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
    let url: URL
    var meta: MediaMetadata
    var isChecked: Bool = false

    // Encode bookkeeping
    var status: EncodeStatus = .queued
    var statusReason: String? = nil
    var finalOutputURL: URL? = nil
    var actualEncodeSeconds: TimeInterval? = nil
    var tempOutputURL: URL? // transient local encoder target; cleaned on success/cancel

    // Progress UI
    var progressMode: ProgressMode = .none
    var progress: Double? = nil            // 0..1
    var etaSeconds: Double? = nil

    // Optional: track output size for any size model you maintain
    var outputSizeBytes: Int64? = nil
    
    var logURL: URL? = nil   // path to per-item ffmpeg log (if any)
    
    var isProcessingMetadata: Bool = false
    var metadataProgress: Double? = nil

    // Caching properties:
    private var _cachedSrcLine: String?
    private var _cachedDstLine: String?
    private var _cachedFileSize: Int64?
    
    mutating func setCachedSrcLine(_ line: String) { _cachedSrcLine = line }
    mutating func setCachedDstLine(_ line: String) { _cachedDstLine = line }
    mutating func setCachedFileSize(_ size: Int64) { _cachedFileSize = size }
    
    var cachedSrcLine: String? { _cachedSrcLine }
    var cachedDstLine: String? { _cachedDstLine }
    var cachedFileSize: Int64? { _cachedFileSize }
    
    init(url: URL, meta: MediaMetadata, status: EncodeStatus = .queued, statusReason: String? = nil) {
        self.url = url
        self.meta = meta
        self.status = status
        self.statusReason = statusReason
        self.isChecked = (status != .blocked)
    }
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

// MARK: - Presets & Droplets Models

/// Represents a saved preset (panel settings only)
struct EncodingPreset: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let createdDate: Date
    var modifiedDate: Date
    var settings: Settings
    
    init(name: String, settings: Settings) {
        self.id = UUID()
        self.name = name
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.settings = settings
    }
    
    mutating func updateSettings(_ newSettings: Settings) {
        self.settings = newSettings
        self.modifiedDate = Date()
    }
    
    // Manual Hashable implementation
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)  // UUID is unique, so we can just hash the ID
    }
    
    // Manual Equatable implementation
    static func == (lhs: EncodingPreset, rhs: EncodingPreset) -> Bool {
        return lhs.id == rhs.id  // Two presets are equal if they have the same ID
    }
}

/// Container for droplet files (.mrhevc)
struct DropletFile: Codable {
    let version: Int = 1
    let createdDate: Date
    let presetName: String
    let settings: Settings
    
    init(presetName: String, settings: Settings) {
        self.createdDate = Date()
        self.presetName = presetName
        self.settings = settings
    }
}

// MARK: - Settings

struct Settings: Codable, Equatable {
    
    // MARK: Run mode
    var runMode: RunMode = .localFFmpeg  // Changed default to Local

    // MARK: Panel state - all panels hidden by default except Presets
    var presetsExpanded: Bool = true      // Keep presets panel open
    var generalExpanded: Bool = false     // "Compression" panel (hidden by default)
    var scaleExpanded: Bool = false       // "Scale & Crop" panel (hidden by default)
    var nclcExpanded: Bool = false        // "NCLC Settings" panel (hidden by default)
    var overlaysExpanded: Bool = false    // "Overlays" panel (hidden by default)
    var deadlineExpanded: Bool = false    // "Deadline Options" panel (hidden by default)

    // MARK: Compression & Resizing
    var bypassHEVC: Bool = false
    var qualityCRF: Int = 18              // Default CRF 18
    var containerFormat: ContainerFormat = .mov  // Default to MOV
    var outputSuffix: String = "-HEVC"    // Default suffix
    
    // MARK: Scale & Crop
    var scale: ScaleOption = .oneToOne
    var scaleSuffix: String = ""

    // MARK: NCLC Settings
    var nclcTag: String = Self.nclcOptionOrderTopFirst.first ?? "No Change"
    var nclcFilenameLabel: String = ""

    // MARK: Auto-Encode (alias for legacy turboMode)
    var autoEncodeOnDrop: Bool = false

    // MARK: Burn-ins
    var burnInFrames: Bool = false
    var burnInTimecode: Bool = false
    var burnInFilename: Bool = false

    var burnInFramesPosition: BurnInPosition   = .lowerRight    // Changed default to lowerRight
    var burnInTimecodePosition: BurnInPosition = .lowerLeft
    var burnInFilenamePosition: BurnInPosition = .lowerRight

    // MARK: Overlay appearance
    var overlayTextColorHex: String = "#FFFFFF"     // White
    var overlayTextColorAlpha: Double = 1.0
    var overlayBoxEnabled: Bool = true
    var overlayBoxColorHex: String = "#000000"      // Black
    var overlayBoxColorAlpha: Double = 0.80

    // MARK: Metadata cache (optional)
    var meta: MediaMetadata = .empty

    // MARK: Deadline - Complete set of options for droplet compatibility
    var deadlineCommandPath: String = ""
    var priority: Int = 50
    var pool: String = ""
    var secondaryPool: String = ""
    var group: String = ""
    var batchName: String = ""
    var jobName: String = ""
    var comment: String = ""
    var dependencies: String = ""
    var deadlineUserHomeBookmark: Data? = nil

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
            if let first = groupOptions.first, (group.isEmpty || !groupOptions.contains(group)) {
                group = first
            }
        }
    }

    var lastDeadlineFetch: Date? = nil
    
    // MARK: Preferences
    var filenameOrder: [FilenamePart] = [.nclc, .scale, .compression]
    
    // MARK: Presets
    var selectedPresetName: String = "Default"
}

// MARK: - Settings Extensions for Presets

extension Settings {
    /// Create a preset-safe copy excluding runtime-only properties but INCLUDING panel states
    func forPreset() -> Settings {
        var copy = self
        // Clear runtime-only properties that shouldn't be in presets
        copy.poolOptions = []
        copy.groupOptions = []
        copy.lastDeadlineFetch = nil
        copy.deadlineUserHomeBookmark = nil
        copy.meta = .empty
        copy.selectedPresetName = "Custom" // Will be overridden when loading
        
        // KEEP panel states - they should be part of presets for UI consistency
        // (presetsExpanded, generalExpanded, scaleExpanded, nclcExpanded, overlaysExpanded, deadlineExpanded)
        
        return copy
    }
    
    /// Create a droplet-safe copy with auto-encode forced on and runtime data removed
    func forDroplet() -> Settings {
        var copy = self.forPreset()
        copy.autoEncodeOnDrop = true
        
        // Remove panel state info from droplets since UI state doesn't apply to CLI mode
        copy.presetsExpanded = true      // Reset to defaults
        copy.generalExpanded = false
        copy.scaleExpanded = false
        copy.nclcExpanded = false
        copy.overlaysExpanded = false
        copy.deadlineExpanded = false
        
        return copy
    }
    
    /// Merge preset settings into current settings, preserving runtime data
    mutating func applyPreset(_ presetSettings: Settings, presetName: String) {
        // Store runtime data that should be preserved
        let preservedPoolOptions = self.poolOptions
        let preservedGroupOptions = self.groupOptions
        let preservedLastFetch = self.lastDeadlineFetch
        let preservedBookmark = self.deadlineUserHomeBookmark
        let preservedMeta = self.meta
        
        // Apply preset settings (including panel states)
        self = presetSettings
        
        // Restore preserved runtime data
        self.poolOptions = preservedPoolOptions
        self.groupOptions = preservedGroupOptions
        self.lastDeadlineFetch = preservedLastFetch
        self.deadlineUserHomeBookmark = preservedBookmark
        self.meta = preservedMeta
        self.selectedPresetName = presetName
        
        // Ensure dropdown defaults are valid with current options
        self.coerceDropdownDefaultsTopFirst()
    }
    
    /// Ensure all Deadline settings are present and valid for droplet export
    mutating func ensureCompleteDeadlineSettings() {
        // Make sure all Deadline properties have default values
        if deadlineCommandPath.isEmpty {
            deadlineCommandPath = ""
        }
        if priority < 0 || priority > 100 {
            priority = 50
        }
        if pool.isEmpty {
            pool = ""
        }
        if secondaryPool.isEmpty {
            secondaryPool = ""
        }
        if group.isEmpty {
            group = ""
        }
        if batchName.isEmpty {
            batchName = ""
        }
        if jobName.isEmpty {
            jobName = ""
        }
        if comment.isEmpty {
            comment = ""
        }
        if dependencies.isEmpty {
            dependencies = ""
        }
        
        // Note: poolOptions and groupOptions are intentionally cleared in forDroplet()
        // since they're runtime/machine-specific
    }
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

// MARK: - Preset Errors

enum PresetError: LocalizedError {
    case nameAlreadyExists
    case presetNotFound
    case invalidName(String)
    case exportFailed(Error)
    case importFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .nameAlreadyExists:
            return "A preset with this name already exists"
        case .presetNotFound:
            return "Preset not found"
        case .invalidName(let reason):
            return "Invalid preset name: \(reason)"
        case .exportFailed(let error):
            return "Export failed: \(error.localizedDescription)"
        case .importFailed(let error):
            return "Import failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Container Format

enum ContainerFormat: String, CaseIterable, Codable, Identifiable {
    case mov = "mov"
    case mp4 = "mp4"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .mov: return "mov"
        case .mp4: return "mp4"
        }
    }
    
    var displayName: String {
        switch self {
        case .mov: return "QuickTime (.mov)"
        case .mp4: return "MP4 (.mp4)"
        }
    }
}
