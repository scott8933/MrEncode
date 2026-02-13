// =============================
// File: UI_HeaderBar.swift - Simple Header Bar
// =============================

import SwiftUI

// Top header bar (stateless). Caller supplies bindings.
struct UI_HeaderBar: View {
    let title: String
    @Binding var runMode: RunMode
    @Binding var autoEncodeOnDrop: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.largeTitle).bold()

            Spacer()

            Picker("Mode", selection: $runMode) {
                ForEach(RunMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .help("Choose Local (ffmpeg) or Remote (Deadline) execution.")

            Toggle("Auto-Encode", isOn: $autoEncodeOnDrop)
                .help("Start encoding immediately when files are dropped.")
                .padding(.leading, 8)
        }
        .padding(.vertical, 4)
    }
}
