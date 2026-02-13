// =============================
// File: UI_ActionBar.swift
// =============================
import SwiftUI

struct UI_ActionBar: View {
    // Inputs from parent
    var canClear: Bool
    var canSubmit: Bool
    var hasEncodingJobs: Bool        // indicates if any jobs are encoding
    var onClear: () -> Void
    var onSubmit: () -> Void
    var onCancelAll: () -> Void      // cancel all encoding jobs
    var runMode: RunMode             // kept for parity; not used for the fixed title
    var hasSelection: Bool           // drives "Clear Selected" vs "Clear All"
    var isBackgroundProcessing: Bool
    @Binding var showPreferences: Bool

    // Ghost labels to keep button widths stable
    private var clearGhost: String { "Clear Selected" }
    private var encodeGhost: String { "Encode" }

    var body: some View {
        let clearTitle  = hasSelection ? "Clear Selected" : "Clear All"
        let encodeTitle = "Encode" // always

        HStack {
            // Left cluster: Gear + Clear + Global Progress (when encoding)
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
                
                // Global Progress + Cancel (only visible when encoding jobs exist)
                if hasEncodingJobs {
                    UI_GlobalProgress(onCancelAll: onCancelAll)
                }
            }

            Spacer()

            // Right: Encode
            ZStack {
                Text(encodeGhost).opacity(0)
                Button(encodeTitle, action: onSubmit)
                    .disabled(!canSubmit || isBackgroundProcessing)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(.clear)
    }
}

// MARK: - Global Progress Component

private struct UI_GlobalProgress: View {
    @EnvironmentObject var state: AppState
    let onCancelAll: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Progress")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    ProgressView(value: state.globalProgress)
                        .frame(width: 100, height: 4)
                    
                    Text(state.globalProgressText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            
            Button("Cancel All") {
                onCancelAll()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundColor(.orange)
            .help("Cancel all running encodes")
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
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
        isBackgroundProcessing: false,
        showPreferences: .constant(false)
    )
    .frame(width: 640)
}
