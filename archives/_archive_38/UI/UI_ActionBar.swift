// =============================
// File: UI_ActionBar.swift
// =============================
import SwiftUI

struct UI_ActionBar: View {
    // Inputs from parent (kept for compatibility with your current ContentView)
    var canClear: Bool
    var canSubmit: Bool
    var hasEncodingJobs: Bool
    var onClear: () -> Void
    var onSubmit: () -> Void
    var onCancelAll: () -> Void
    var runMode: RunMode
    var hasSelection: Bool
    var isBackgroundProcessing: Bool
    @Binding var showPreferences: Bool

    @EnvironmentObject var state: AppState

    // Ghost labels to keep button widths stable and avoid UI jumps
    private var clearGhost: String { "Clear Selected" }
    private var encodeGhost: String { "Encode" }

    var body: some View {
        let clearTitle  = hasSelection ? "Clear Selected" : "Clear All"
        let encodeTitle = "Encode"

        HStack(spacing: 12) {
            // LEFT CLUSTER: Gear only (Prefs stays on the left)
            HStack(spacing: 8) {
                Button {
                    showPreferences = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Preferences")
            }


            // MIDDLE: stretchy global progress with centered label
            if hasEncodingJobs {
                ZStack(alignment: .center) {
                    ProgressView(value: state.globalProgress) // 0...1
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity, minHeight: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                    Text(progressOverlayLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .allowsHitTesting(false)
                        .padding(.horizontal, 6)
                }
            } else {
                // keep layout symmetrical when idle
                Spacer(minLength: 0)
            }

            // RIGHT CLUSTER: Cancel (secondary) + Clear (secondary) + Encode (primary)
            HStack(spacing: 8) {
                if hasEncodingJobs {
                    Button("Cancel") { onCancelAll() }
                        .buttonStyle(.bordered)
                        .help("Cancel all running encodes")
                }

                // Clear Selected / Clear All (single button; label switches by hasSelection)
                ZStack(alignment: .center) {
                    Text(clearGhost).opacity(0) // ghost to stabilize width
                    Button(clearTitle, action: onClear)
                        .disabled(!canClear)
                }

                // Encode (primary, far right)
                ZStack(alignment: .center) {
                    Text(encodeGhost).opacity(0) // ghost to stabilize width
                    Button(encodeTitle, action: onSubmit)
                        .disabled(!canSubmit || isBackgroundProcessing)
                        .buttonStyle(.borderedProminent)
                        .help(isBackgroundProcessing ? "Busy preparing files…" : "Start encoding checked items")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(.clear)
    }
    
    private var progressOverlayLabel: String {
        let pct = Int((state.globalProgress * 100).rounded())
        if let eta = summedETASeconds(),
           eta > 0,
           let text = Self.etaFormatter.string(from: eta) {
            return "\(pct)% • \(text) left"
        } else {
            return "\(pct)%"
        }
    }

    private func summedETASeconds() -> TimeInterval? {
        let etas = state.files
            .filter { $0.status == .encoding }
            .compactMap { $0.etaSeconds }
        return etas.isEmpty ? nil : etas.reduce(0, +)
    }

    private static let etaFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = [.dropAll]
        return f
    }()
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
    .environmentObject(AppState()) // if you have a lightweight init
    .frame(width: 820)
}
