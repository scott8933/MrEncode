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

            // RIGHT CLUSTER: Cancel (secondary) + Queued count + Clear (secondary) + Encode (primary)
            HStack(spacing: 8) {
                if hasEncodingJobs {
                    Button("Cancel") { onCancelAll() }
                        .buttonStyle(.bordered)
                        .help("Cancel all running encodes")
                }

                // Queued count (checked items) — lightweight status next to Clear
                let queued = state.files.filter { $0.isChecked }.count
                let total  = state.files.count
                Text("Queued: \(queued) of \(total)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                // Clear Selected / Clear All
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

        if let eta = remainingSeconds(files: state.files, settings: state.settings),
           eta > 0,
           let text = Self.etaFormatter.string(from: eta) {
            return "\(pct)% • \(text) left"
        } else {
            return "\(pct)%"
        }
    }

    /// Global remaining time =
    ///  - For .encoding items: only the remaining portion (uses progress if available)
    ///  - For .queued items that are checked: full estimate
    ///  - Ignore done/error/blocked/un-checked items
    private func remainingSeconds(files: [MediaItem], settings: Settings) -> TimeInterval? {
        var total: TimeInterval = 0
        var sawAny = false

        for item in files {
            // Skip items that don't participate
            if item.status == .done || item.status == .error || item.status == .blocked {
                continue
            }
            if item.status == .queued && !item.isChecked {
                continue
            }

            // Ask estimator for total expected runtime for this item
            guard let estimate = EncodeTimeEstimator.estimateSeconds(
                url: item.url,
                meta: item.meta,
                settings: settings,
                runMode: settings.runMode
            ), estimate.isFinite, estimate > 0 else {
                continue
            }

            // Use only remaining for encoding; full estimate for queued & checked
            let add: TimeInterval
            if item.status == .encoding, let p = item.progress, p.isFinite, p >= 0, p <= 1 {
                add = max(0, estimate * (1 - p))
            } else if item.status == .queued && item.isChecked {
                add = estimate
            } else if item.status == .encoding {
                // encoding but no progress reading yet -> assume full estimate
                add = estimate
            } else {
                continue
            }

            total += add
            sawAny = true
        }

        return sawAny ? total : nil
    }

    private static let etaFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = [.dropAll]
        return f
    }()
}
