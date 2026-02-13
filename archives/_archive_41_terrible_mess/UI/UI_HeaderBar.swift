// =============================
// File: UI_HeaderBar.swift - Simple Header Bar
// =============================

import SwiftUI

struct UI_HeaderBar: View {
    let title: String
    @Binding var runMode: RunMode
    @Binding var autoEncodeOnDrop: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.largeTitle).bold()

            Spacer()

            // Segmented control, original style, no "Mode" label
            Picker("", selection: $runMode) {   // <- label removed
                Text("Local").tag(RunMode.localFFmpeg)
                Text("Deadline").tag(RunMode.remoteDeadline)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)                  // was 300; narrower for shorter labels
            .help("Choose where the encode will run.")

            // Keep regular-size checkbox (not .small)
            Toggle("Auto-Encode", isOn: $autoEncodeOnDrop)
                .help("Start encoding immediately when files are dropped.")
                .padding(.leading, 8)
        }
        .padding(.vertical, 4)
    }
}
