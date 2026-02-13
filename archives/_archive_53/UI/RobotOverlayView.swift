//
//  RobotOverlayView.swift
//  MrEncode
//
//  Created by scott ulrich on 1/26/26.
//


#if os(macOS)
import AppKit
#endif
import SwiftUI

struct RobotModeOverlayView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Button {
            // Clicking anywhere exits Robot Mode
            state.isRobotMode = false
        } label: {
            ZStack {
                StyleConstants.globalBackground
                    .ignoresSafeArea()

                if NSImage(named: "Robot") != nil {
                    Image("Robot")
                        .resizable()
                        .scaledToFit()
                        .padding(48)
                } else {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: 220, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .focusable() // allows Esc to work
        .onExitCommand {
            state.isRobotMode = false
        }
    }
}
