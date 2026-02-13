// =============================
// File: UI_HeaderBar.swift - Simple Header Bar
// =============================

// UI_HeaderBar.swift — use consolidated widths from AppColors

import SwiftUI

struct UI_HeaderBar: View {
    let title: String
    @Binding var runMode: RunMode
    @Binding var autoEncodeOnDrop: Bool

    var body: some View {
        HStack(spacing: StyleConstants.headerSpacing) {
            Text(title)
                .font(.largeTitle).bold()

            Spacer(minLength: 0)

            Picker("", selection: $runMode) {
                Text("Local").tag(RunMode.localFFmpeg)
                Text("Deadline").tag(RunMode.remoteDeadline)
            }
            .pickerStyle(.segmented)
            .frame(minWidth: StyleConstants.headerPickerMinWidth,
                   idealWidth: StyleConstants.headerPickerIdealWidth)
            .help("Choose where the encode will run.")

            Toggle("Auto-Encode", isOn: $autoEncodeOnDrop)
                .frame(minWidth: StyleConstants.headerToggleMinWidth, alignment: .leading)
                .help("Start encoding immediately when files are dropped.")
        }
        .padding(.vertical, StyleConstants.headerBarVerticalPadding)
    }
}
