//
//  AppState+Logging.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/10/25.
//


// =============================
// File: AppState+Logging.swift
// =============================
import Foundation

extension AppState {
    /// Minimal logging hook used by EncodeLocal / EncodeRemote.
    /// Appends a concise line and keeps the list bounded.
    func log(_ level: LogLevel, _ message: String, fileURL: URL? = nil, autoReveal: Bool = false) {
        // Construct entry (matches the fields used by UI_LogPane)
        let entry = AppLogEntry(
            date: Date(),
            level: level,
            message: message,
            filename: fileURL?.lastPathComponent
        )
        // Append + trim to a modest size (avoid debug-dump feel)
        logs.append(entry)
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }

        // If your AppState has a `showLogPane` property and you want auto-reveal on problems,
        // you can uncomment the next two lines. Otherwise, this safely does nothing more.
        /*
        if autoReveal && level != .info {
            showLogPane = true
        }
        */

        #if DEBUG
        let name = fileURL?.lastPathComponent ?? "-"
        print("[\(level.rawValue.uppercased())] \(name): \(message)")
        #endif
    }
}
