// =============================
// File: UI_ActionBar.swift
// =============================
import SwiftUI

struct UI_ActionBar: View {
    // Inputs from parent
    var canClear: Bool
    var canSubmit: Bool
    var onClear: () -> Void
    var onSubmit: () -> Void
    var runMode: RunMode          // kept for parity; not used for the fixed title
    var hasSelection: Bool        // drives "Clear Selected" vs "Clear All"
    @Binding var showPreferences: Bool

    // Ghost labels to keep button widths stable
    private var clearGhost: String { "Clear Selected" }
    private var encodeGhost: String { "Encode" }

    var body: some View {
        let clearTitle  = hasSelection ? "Clear Selected" : "Clear All"
        let encodeTitle = "Encode" // always

        HStack {
            // Left cluster: Gear + Clear
            HStack(spacing: 8) {
                Button {
                    showPreferences = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Preferences")

                ZStack {
                    Text(clearGhost).opacity(0)
                    Button(clearTitle, action: onClear)
                        .disabled(!canClear)
                }
            }

            Spacer()

            // Right: Encode
            ZStack {
                Text(encodeGhost).opacity(0)
                Button(encodeTitle, action: onSubmit)
                    .disabled(!canSubmit)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(.clear)
    }
}

// Optional preview
#Preview {
    UI_ActionBar(
        canClear: true,
        canSubmit: true,
        onClear: {},
        onSubmit: {},
        runMode: .localFFmpeg,
        hasSelection: true,
        showPreferences: .constant(false)
    )
    .frame(width: 640)
}
