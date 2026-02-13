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

    var body: some Commands {

        // File menu items for queue + import
        CommandGroup(after: .importExport) {
            Divider()

            Button("Import Media…") {
                NotificationCenter.default.post(name: .mrEncodeImportMediaRequested, object: nil)
            }

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
    }
}
