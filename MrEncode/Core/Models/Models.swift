// =============================
// File: Models.swift - Complete Revised with Preset Support
// =============================

import Foundation
import AVFoundation


// MARK: - UI Theme

/// UI appearance selection persisted in Settings.
/// This is intentionally UI-agnostic; mapping to SwiftUI's ColorScheme happens in the app layer.
enum UIThemeSelection: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}


// MARK: - Encoding settings

public enum VideoCodec: String, Codable, CaseIterable {
    case hevc422   // H.265 4:2:2 10-bit (Main42210)
    case hevc420   // H.265 4:2:0 10-bit (Main10)
    case h264        // H.264
    case bypass      // No Recompression
}



// MARK: - Run Mode

enum RunMode: String, CaseIterable, Codable, Identifiable {
    case localNative     = "Local"
    case remoteDeadline  = "Deadline"

    var id: String { rawValue }
}



// MARK: UI
var uiTheme: UIThemeSelection = .system



// MARK: - Scale and Custom Scale

enum CustomScaleMode: String, CaseIterable, Codable, Identifiable {
    case stretch = "Stretch"   // Force exact size
    case fit     = "Fit"       // Letterbox / Pillarbox
    case fill    = "Fill"      // Crop
    var id: String { rawValue }
}

enum ScaleOption: String, CaseIterable, Codable, Identifiable {
    case oneToOne = "1:1 (No Scale)"
    case half     = "1/2"
    case quarter  = "1/4"
    case custom   = "Custom"

    var id: String { rawValue }

    var factor: Double {
        switch self {
        case .oneToOne: return 1.0
        case .half:     return 0.5
        case .quarter:  return 0.25
        case .custom:   return 1.0 // not used
        }
    }
}

// MARK: - Burn-in positions

enum BurnInPosition: String, CaseIterable, Codable, Identifiable {
    case upperLeft
    case upperCenter
    case upperRight
    case middleLeft
    case center
    case middleRight
    case lowerLeft
    case lowerCenter
    case lowerRight

    var id: String { rawValue }
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

// Orderable pieces for filename assembly
enum FilenamePart: String, Codable, CaseIterable, Identifiable {
    case nclc, scale, compression, overlays
    var id: String { rawValue }
    var label: String {
        switch self {
        case .nclc:        return "NCLC"
        case .scale:       return "Scale"
        case .compression: return "Compression"
        case .overlays:    return "Overlays"
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
    var id: UUID = UUID()
    var name: String
    var settings: Settings

    var createdDate: Date = Date()
    var modifiedDate: Date = Date()

    var rawSettings: [String: Any]? = nil

    private enum CodingKeys: String, CodingKey {
        case id, name, settings, createdDate, modifiedDate
    }

    mutating func updateSettings(_ newSettings: Settings) {
        settings = newSettings
        modifiedDate = Date()
    }

    static func == (lhs: EncodingPreset, rhs: EncodingPreset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}



/// Container for droplet files (.mrencode)
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

    // Default values ship with Resources/default_prefs.json.
    
    // MARK: - UI Appearance
    var uiTheme: UIThemeSelection = .system

    // MARK: Run mode
    var runMode: RunMode

    // MARK: Panel state - all panels hidden by default except Presets
    var presetsExpanded: Bool
    var generalExpanded: Bool
    var scaleExpanded: Bool
    var nclcExpanded: Bool
    var overlaysExpanded: Bool
    var deadlineExpanded: Bool

    // MARK: Compression & Resizing
    var codec: VideoCodec
    var bypassHEVC: Bool
    var qualityCRF: Int
    var containerFormat: ContainerFormat
    var outputSuffix: String
    
    // MARK: Scale & Crop
    var scale: ScaleOption
    var scaleSuffix: String
    
    // MARK: Custom Scale (optional for backward compatibility)
    var customScaleWidthRaw: Int? = nil
    var customScaleHeightRaw: Int? = nil
    var customScaleModeRaw: CustomScaleMode? = nil
    var customScaleAnchorRaw: BurnInPosition? = nil
    var customScaleAnchorCenterRaw: Bool? = nil

    // Public (non-optional) helpers for UI / command builder
    var customScaleWidth: Int {
        get { max(2, customScaleWidthRaw ?? 1920) }
        set { customScaleWidthRaw = max(2, newValue) }
    }

    var customScaleHeight: Int {
        get { max(2, customScaleHeightRaw ?? 1080) }
        set { customScaleHeightRaw = max(2, newValue) }
    }

    var customScaleMode: CustomScaleMode {
        get { customScaleModeRaw ?? .fit }
        set { customScaleModeRaw = newValue }
    }

    var customScaleAnchor: BurnInPosition {
        get { customScaleAnchorRaw ?? .upperLeft }
        set { customScaleAnchorRaw = newValue }
    }

    var customScaleAnchorCenter: Bool {
        get { customScaleAnchorCenterRaw ?? true }
        set { customScaleAnchorCenterRaw = newValue }
    }
    
    // MARK: Backend (hidden for now; preserves preset compatibility)
    var useEncodeGUIRaw: Bool? = nil

    var useEncodeGUI: Bool {
        get { useEncodeGUIRaw ?? false }
        set { useEncodeGUIRaw = newValue }
    }

    // MARK: NCLC Settings
    var nclcTag: String
    var nclcFilenameLabel: String

    // MARK: Auto-Encode (alias for legacy turboMode)
    var autoEncodeOnDrop: Bool = false

    // MARK: Audio
    // Stored (Codable-safe for older JSON that lacks this key)
    var doneChimeVolumeRaw: Double? = nil

    // Public (always non-optional, with default)
    var doneChimeVolume: Double {
        get { doneChimeVolumeRaw ?? 0.30 }
        set { doneChimeVolumeRaw = min(max(newValue, 0.0), 1.0) }
    }

    // MARK: Burn-ins
    var burnInFrames: Bool
    var burnInTimecode: Bool
    var burnInFilename: Bool

    var burnInFramesPosition: BurnInPosition
    var burnInTimecodePosition: BurnInPosition
    var burnInFilenamePosition: BurnInPosition

    // MARK: Overlay appearance
    var overlayTextColorHex: String
    var overlayTextColorAlpha: Double
    var overlayBoxEnabled: Bool
    var overlayBoxColorHex: String
    var overlayBoxColorAlpha: Double
    
    // MARK: Overlay filename suffix
    var overlaySuffix: String
    
    // MARK: Metadata cache (optional)
    var meta: MediaMetadata

    // MARK: Deadline - Complete set of options for droplet compatibility
    var deadlineCommandPath: String
    var priority: Int
    var pool: String
    var secondaryPool: String
    var group: String
    var batchName: String
    var jobName: String
    var comment: String
    var dependencies: String
    var deadlineUserHomeBookmark: Data?

    var poolOptions: [String] {
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
    var groupOptions: [String] {
        didSet {
            if let first = groupOptions.first, (group.isEmpty || !groupOptions.contains(group)) {
                group = first
            }
        }
    }

    var lastDeadlineFetch: Date?
    
    // MARK: Preferences
    var filenameOrder: [FilenamePart]
    var suffixSeparator: String
    
    // MARK: Presets
    var selectedPresetName: String
}

// MARK: - Settings Extensions for Presets

extension Settings {

    // ---------------------------------------------------------
    // MARK: - Preset / Droplet lifecycle
    // ---------------------------------------------------------

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
        // (presetsExpanded, generalExpanded, scaleExpanded, nclcExpanded,
        //  overlaysExpanded, deadlineExpanded)

        return copy
    }

    /// Create a droplet-safe copy with auto-encode forced on and runtime data removed
    func forDroplet() -> Settings {
        var copy = self.forPreset()
        copy.autoEncodeOnDrop = true

        // Remove panel state info from droplets since UI state doesn't apply to CLI mode
        copy.presetsExpanded = true
        copy.generalExpanded = false
        copy.scaleExpanded = false
        copy.nclcExpanded = false
        copy.overlaysExpanded = false
        copy.deadlineExpanded = false

        return copy
    }

    /// Merge preset settings into current settings, preserving runtime data
    mutating func applyPreset(_ presetSettings: Settings, presetName: String) {
        // Preserve runtime data
        let preservedPoolOptions = poolOptions
        let preservedGroupOptions = groupOptions
        let preservedLastFetch = lastDeadlineFetch
        let preservedBookmark = deadlineUserHomeBookmark
        let preservedMeta = meta

        // Apply preset settings (including panel states)
        self = presetSettings

        // Restore preserved runtime data
        poolOptions = preservedPoolOptions
        groupOptions = preservedGroupOptions
        lastDeadlineFetch = preservedLastFetch
        deadlineUserHomeBookmark = preservedBookmark
        meta = preservedMeta
        selectedPresetName = presetName

        // Ensure dropdown defaults are valid with current options
        coerceDropdownDefaultsTopFirst()
    }

    /// Ensure all Deadline settings are present and valid for droplet export
    mutating func ensureCompleteDeadlineSettings() {
        if deadlineCommandPath.isEmpty { deadlineCommandPath = "" }
        if priority < 0 || priority > 100 { priority = 50 }
        if pool.isEmpty { pool = "" }
        if secondaryPool.isEmpty { secondaryPool = "" }
        if group.isEmpty { group = "" }
        if batchName.isEmpty { batchName = "" }
        if jobName.isEmpty { jobName = "" }
        if comment.isEmpty { comment = "" }
        if dependencies.isEmpty { dependencies = "" }

        // poolOptions / groupOptions intentionally excluded (runtime-only)
    }

    // ---------------------------------------------------------
    // MARK: - Modified detection (preset JSON is source of truth)
    // ---------------------------------------------------------

    enum PanelID: String, CaseIterable {
        case compression
        case scaleCrop
        case nclc
        case overlays
        case deadline
        case presets
    }

    /// Keys to compare per panel (JSON keys, not Swift property names)
    static let panelKeyWhitelist: [PanelID: [String]] = [
        .compression: [
            "codec",
            "bitrate",
            "quality",
            "outputSuffix"
        ],
        .scaleCrop: [
            "scale",
            "scaleWidth",
            "scaleHeight",
            "scaleSuffix",
            "scaleAnchor"
        ],
        .nclc: [
            "nclcTag",
            "nclcFilenameLabel"
        ],
        .overlays: [
            "burnInFrames",
            "burnInTimecode",
            "burnInFilename",
            "burnInFramesPosition",
            "burnInTimecodePosition",
            "burnInFilenamePosition",
            "overlayBoxEnabled",
            "overlayTextColorHex",
            "overlayTextColorAlpha",
            "overlayBoxColorHex",
            "overlayBoxColorAlpha",
            "overlaySuffix"
        ],
        .deadline: [
            "runMode",
            "priority",
            "pool",
            "secondaryPool",
            "group",
            "batchName",
            "jobName",
            "comment",
            "dependencies"
        ]
    ]

    /// Keys that should NEVER participate in modified detection
    static let modifiedIgnoreKeys: Set<String> = [
        "presetsExpanded",
        "generalExpanded",
        "scaleExpanded",
        "nclcExpanded",
        "overlaysExpanded",
        "deadlineExpanded",
        "selectedPresetName",
        "meta"
    ]

    /// Determine if a panel is modified relative to RAW preset JSON
    func isPanelModified(
        _ panel: PanelID,
        baselineRaw: [String: Any]
    ) -> Bool {

        // Presets panel aggregates all others
        if panel == .presets {
            return PanelID.allCases
                .filter { $0 != .presets }
                .contains { isPanelModified($0, baselineRaw: baselineRaw) }
        }

        // Overlay panel: if it is logically inactive, it cannot be "modified"
        if panel == .overlays && isOverlaysPanelInactive {
            return false
        }

        guard
            let keys = Self.panelKeyWhitelist[panel],
            let currentDict = Self.toJSONDictionary(self)
        else { return false }

        for key in keys where !Self.modifiedIgnoreKeys.contains(key) {

            // Intersection-only: only compare keys that exist in BOTH
            guard
                let currentValue = currentDict[key],
                let baselineValue = baselineRaw[key]
            else { continue }

            if !Self.jsonValuesEqual(currentValue, baselineValue) {
                return true
            }
        }

        return false
    }


    // ---------------------------------------------------------
    // MARK: - JSON helpers (private)
    // ---------------------------------------------------------

    /// Convert Settings → JSON dictionary using same encoder path as presets
    static func toJSONDictionary(_ settings: Settings) -> [String: Any]? {
        do {
            let data = try JSONEncoder().encode(settings.forPreset())
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            return obj as? [String: Any]
        } catch {
            return nil
        }
    }

    /// Loose JSON equality (numbers, bools, strings, arrays)
    static func jsonValuesEqual(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case let (x as NSNumber, y as NSNumber):
            return x == y
        case let (x as String, y as String):
            return x == y
        case let (x as Bool, y as Bool):
            return x == y
        case let (x as [Any], y as [Any]):
            return x.count == y.count && zip(x, y).allSatisfy(jsonValuesEqual)
        default:
            return false
        }
    }
}



// MARK: - Sanity helpers - (prevent source overwrites)

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
}

extension Settings {
    /// Compression panel considered "inactive" when it's a pass-through AND no compression suffix.
    /// (Keep it independent of Scale/NCLC/Overlays.)
    var isCompressionPanelInactive: Bool {
        (codec == .bypass || bypassHEVC) && outputSuffix.trimmed.isEmpty
    }

    /// Scale panel considered "inactive" when 1:1 and no scale suffix.
    var isScalePanelInactive: Bool {
        scale == .oneToOne && scaleSuffix.trimmed.isEmpty
    }

    /// NCLC panel considered "inactive" when dropdown says No Change and label is empty.
    var isNclcPanelInactive: Bool {
        nclcTag.trimmed.lowercased() == "no change" && nclcFilenameLabel.trimmed.isEmpty
    }

    /// Overlays panel inactive when no burn-ins are enabled AND no overlay suffix.
    /// (Allows “filename-only” use cases if you ever want them.)
    var isOverlaysPanelInactive: Bool {
        let noBurn = !(burnInFrames || burnInTimecode || burnInFilename)
        let noSuffix = overlaySuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return noBurn && noSuffix
    }


    /// All panels together would do nothing.
    var isEverythingInactive: Bool {
        isCompressionPanelInactive && isScalePanelInactive && isNclcPanelInactive && isOverlaysPanelInactive
    }

    /// All filename-affecting suffix inputs are blank → output name equals input base name.
    var bothSuffixesBlank: Bool {
        outputSuffix.trimmed.isEmpty
        && scaleSuffix.trimmed.isEmpty
        && nclcFilenameLabel.trimmed.isEmpty
        && overlaySuffix.trimmed.isEmpty
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


// MARK: - Deadline validation helpers
extension Settings {
    /// Validates that Pool is set (not "none"/empty) when in Deadline mode.
    var deadlinePoolsValid: Bool {
        if runMode != .remoteDeadline { return true }
        return !pool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pool.lowercased() != "none"
    }
}
