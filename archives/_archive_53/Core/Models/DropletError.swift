//
//  DropletError.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/18/25.
//

import Foundation

/// Describes droplet processing failures shared by CLI and GUI wrappers.
enum DropletError: Error, Equatable {
    case validation(message: String)
    case encodeFailed(message: String)
    case deadlineFailed(message: String)
    case cancelled(message: String)
}

extension DropletError {
    /// Human readable description suitable for logs and alerts.
    var message: String {
        switch self {
        case .validation(let message),
             .encodeFailed(let message),
             .deadlineFailed(let message),
             .cancelled(let message):
            return message
        }
    }

    /// High-level category title; callers can extend if they need richer UI.
    var title: String {
        switch self {
        case .validation:
            return "Validation Error"
        case .encodeFailed:
            return "Encoding Failed"
        case .deadlineFailed:
            return "Deadline Submission Failed"
        case .cancelled:
            return "Encoding Cancelled"
        }
    }

    /// Suggested log level for UI messaging.
    var logLevel: LogLevel {
        switch self {
        case .validation:
            return .warning
        case .encodeFailed, .deadlineFailed:
            return .error
        case .cancelled:
            return .info
        }
    }

    /// Best-effort mapping to AppState log codes for filtering.
    var logCode: LogCode? {
        switch self {
        case .validation(let message):
            if message.localizedCaseInsensitiveContains("deadline") ||
               message.localizedCaseInsensitiveContains("render farm") {
                return .farmPath
            }
            if message.localizedCaseInsensitiveContains("overwrite") {
                return .wouldOverwrite
            }
            if message.localizedCaseInsensitiveContains("nothing would be changed") {
                return .noOp
            }
            return .other
        case .encodeFailed:
            return .other
        case .deadlineFailed:
            return .other
        case .cancelled:
            return .other
        }
    }
}
