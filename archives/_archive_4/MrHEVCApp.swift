//
//  MrHEVCApp.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/1/25.
//
// =============================
// File: MrHEVCApp.swift
// =============================


import SwiftUI
import AppKit

// AppKit delegate so closing the last window quits the app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true // Quit when the last window is closed (red close-dot)
    }
}

@main
struct MrHEVCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(" ") {   // empty string = no small title in title bar
            ContentView()
                .environmentObject(appState)
                .task { appState.bootstrapDeadlineLists() }
        }
        // Set default size when the window first opens
        .defaultSize(width: 700, height: 900)
        // Restrict resizing so window can’t shrink below content's min size
        .windowResizability(.contentSize)
        .commands {
            // optional, keep app menu clean
        }
    }
}
