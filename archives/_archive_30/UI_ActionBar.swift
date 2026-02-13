// =============================
// File: UI_ActionBar.swift
// =============================
import SwiftUI

struct UI_ActionBar: View {
    // Inputs from parent
    var canClear: Bool
    var canSubmit: Bool
    var hasEncodingJobs: Bool        // NEW: indicates if any jobs are encoding
    var onClear: () -> Void
    var onSubmit: () -> Void
    var onCancelAll: () -> Void      // NEW: cancel all encoding jobs
    var runMode: RunMode          // kept for parity; not used for the fixed title
    var hasSelection: Bool        // drives "Clear Selected" vs "Clear All"
    @Binding var showPreferences: Bool

    // Ghost labels to keep button widths stable
    private var clearGhost: String { "Clear Selected" }
    private var encodeGhost: String { "Encode" }
    private var cancelGhost: String { "Cancel All" }

    var body: some View {
        let clearTitle  = hasSelection ? "Clear Selected" : "Clear All"
        let encodeTitle = "Encode" // always

        HStack {
            // Left cluster: Gear + Clear + Cancel All (when encoding)
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
                
                // Cancel All button (only visible when encoding jobs exist)
                if hasEncodingJobs {
                    ZStack {
                        Text(cancelGhost).opacity(0)
                        Button("Cancel All") {
                            onCancelAll()
                        }
                        .foregroundColor(.orange)
                        .help("Cancel all running encodes")
                    }
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
        hasEncodingJobs: true,
        onClear: {},
        onSubmit: {},
        onCancelAll: {},
        runMode: .localFFmpeg,
        hasSelection: true,
        showPreferences: .constant(false)
    )
    .frame(width: 640)
}
