//
//  AppDelegate.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/7/25.
//


import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        if filename.lowercased().hasSuffix(".mov") {
            let url = URL(fileURLWithPath: filename)
            // Post a distributed notification or use NotificationCenter to pass this to AppState
            NotificationCenter.default.post(name: .mrhevcFileDrop, object: nil, userInfo: ["url": url])
            return true
        }
        return false
    }
}

extension Notification.Name {
    static let mrhevcFileDrop = Notification.Name("MrHEVC.FileDrop")
}
