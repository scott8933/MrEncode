//
//  MrEncodeCommands.swift
//  MrEncode
//
//  Created by scott ulrich on 1/21/26.
//


// AppCommands.swift

import SwiftUI

struct MrEncodeCommands: Commands {
    @ObservedObject private var state = AppState.shared!
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {

        // File menu items for queue + import
        CommandGroup(after: .importExport) {
            Divider()

            Button("Import Media…") {
                NotificationCenter.default.post(name: .mrEncodeImportMediaRequested, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command])

            Divider()

            Button("Save Queue…") {
                NotificationCenter.default.post(name: .mrEncodeSaveQueueRequested, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Open Queue…") {
                NotificationCenter.default.post(name: .mrEncodeOpenQueueRequested, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Append Queue…") {
                NotificationCenter.default.post(name: .mrEncodeAppendQueueRequested, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
        }

        // Your existing command group
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Duplicate") {
                state.duplicateSelected()
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(state.selectedIDs.isEmpty)
        }

        // Help menu items (standard macOS Help menu)
        // Replace the system Help menu (removes the default “MrEncode Help” that opens Help Viewer)
        CommandGroup(replacing: .help) {

            Button("MrEncode Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: [.command])

            Button("Keyboard Shortcuts") {
                HelpRouting.shared.requestedTopic = .keyboardShortcuts
                openWindow(id: "help")
            }

            Divider()

            Button("Visit GrayRobot Website") {
                if let url = URL(string: "https://grayrobot.io") {
                    NSWorkspace.shared.open(url)
                }
            }
            
             Button("Debug ▸ Export Droplet JSON") {
                DebugDropletExporter.export()
             }

            // Optional: quick access to your log window from Help
            // Divider()
            // Button("Open Log Window") {
            //     openWindow(id: "log-viewer")
            // }
        }
    }
}
