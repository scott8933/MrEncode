// =============================
// File: UI_MessageArea.swift (compact, non-greedy footer)
// =============================
import SwiftUI
import AppKit

struct UI_MessageArea: View {
    @EnvironmentObject var state: AppState
    @State private var expanded: Set<UUID> = []

    // Keep the original “show a few recent items” behavior
    private var recent: [AppLogEntry] {
        Array(state.uiMessages.suffix(3)).reversed() // newest first
    }

    var body: some View {
        if recent.isEmpty {
            // Original behavior: unobtrusive — don’t render anything when empty
            EmptyView()
        } else {
            let latestID = recent.first?.id
            let collapsed = expanded.isEmpty

            // Base content (matches the Original compact card look/feel)
            let content = VStack(alignment: .leading, spacing: 6) {
                ForEach(recent) { m in
                    UI_MessageRowCompact(
                        entry: m,
                        isExpanded: expanded.contains(m.id),
                        onToggle: { toggle(m.id) }
                    )
                    .opacity(m.id == latestID ? 1.0 : 0.5) // newest full, older 50%
                }
            }
            .padding(8)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

            // Preserve the “small footer” feel unless a row is expanded.
            Group {
                if collapsed {
                    content.frame(maxHeight: 84) // “a few lines as necessary but no taller”
                } else {
                    content // allow to grow just when details are shown
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

private struct UI_MessageRowCompact: View {
    let entry: AppLogEntry
    let isExpanded: Bool
    let onToggle: () -> Void

    private let bullet = " — " // matches original look for inline filename

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main line (Original look, with small chevron added)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Circle()
                    .fill(color(for: entry.level))
                    .frame(width: 8, height: 8)

                Text(mainLine(entry))
                    .font(.callout)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }

            // Detail view (borrowed from the New layout, simplified to avoid new model deps)
            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    Text(timestamp(entry.date))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let name = entry.filename, !name.isEmpty {
                        Text("File: \(name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    // If you later add AppLogEntry.logURL, you can enable a live "Reveal Log" button:
                    // if let url = entry.logURL {
                    //     Button("Reveal Log") {
                    //         NSWorkspace.shared.activateFileViewerSelecting([url])
                    //     }
                    //     .buttonStyle(.link)
                    //     .font(.caption)
                    // }
                }
                .padding(.leading, 20) // align detail under text (chevron + dot + gap)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    // MARK: - Formatting helpers
    private func mainLine(_ e: AppLogEntry) -> String {
        // Keep original inline filename placement when present
        if let fn = e.filename, !fn.isEmpty {
            return "\(prefix(for: e.level))\(e.message)\(bullet)\(fn)"
        } else {
            return "\(prefix(for: e.level))\(e.message)"
        }
    }

    private func prefix(for level: LogLevel) -> String {
        switch level {
        case .info:    return ""
        case .warning: return "Warning: "
        case .error:   return "Error: "
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info:    return Color.blue.opacity(0.9)
        case .warning: return Color.orange.opacity(0.9)
        case .error:   return Color.red.opacity(0.9)
        }
    }

    private func timestamp(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df.string(from: date)
    }
}
