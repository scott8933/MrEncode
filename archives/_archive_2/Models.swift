// =============================
// File: Models.swift
// =============================
import Foundation

enum MediaStatus: String, Codable {
    case queued
    case encoding
    case done
    case error
    case blocked   // not farm-accessible (e.g., Desktop/Downloads/local home)
}

struct MediaItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var status: MediaStatus = .queued
    var statusReason: String? = nil  // short explanation for blocked/error
}


enum RunMode: String, Codable, CaseIterable, Identifiable {
    case localFFmpeg   = "Local (ffmpeg)"
    case remoteDeadline = "Remote (Deadline)"
    var id: String { rawValue }
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

    // Deadline
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
