// =============================
// File: AppDelegate.swift
// =============================


import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    // Intentionally no openFile handler:
    // FileDropHandler (installed at app start) is the single canonical entry for drops/opens.
}

// Kept for source compatibility if any notifications referenced it previously.
extension Notification.Name {
    static let mrencodeFileDrop = Notification.Name("MrEncode.FileDrop")
}
