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

@main
struct MrHEVCApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(" ") {   // <- empty string means no small title in the title bar
            ContentView()
                .environmentObject(appState)
                .task { appState.bootstrapDeadlineLists() }
        }
        // Set default size when the window first opens
        .defaultSize(width: 900, height: 700)
        // Restrict resizing so window can’t shrink below min
        .windowResizability(.contentSize)
        .commands {
            // optional, keep app menu clean
        }
    }
}
