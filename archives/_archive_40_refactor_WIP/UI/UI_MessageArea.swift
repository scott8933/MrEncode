// UI_MessageArea.swift — compact footer + real chevron Detail + both buttons
import SwiftUI
import AppKit

struct UI_MessageArea: View {
    @EnvironmentObject var state: AppState
    @State private var expanded: Set<UUID> = []

    private var recent: [AppLogEntry] {
        Array(state.uiMessages.suffix(3)).reversed() // newest first
    }

    var body: some View {
        if recent.isEmpty {
            EmptyView()
        } else {
            let latestID = recent.first?.id
            let collapsed = expanded.isEmpty

            let content = VStack(alignment: .leading, spacing: 6) {
                ForEach(recent) { m in
                    UI_MessageRowCompact(
                        entry: m,
                        isExpanded: expanded.contains(m.id),
                        onToggle: { toggle(m.id) }
                    )
                    .opacity(m.id == latestID ? 1.0 : 0.5)
                }
            }
            .padding(8)
            
            // --- Translucent backdrop ---
            .background(
                Group {
                    if #available(macOS 12.0, *) {
                        Rectangle().fill(.ultraThinMaterial).opacity(0.55)   // slightly more see-through than .thinMaterial
                    } else {
                        Color(nsColor: .windowBackgroundColor).opacity(0.80) // fallback
                    }
                }
            )
            
            // --- Shape + subtle border (as before) ---
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

            // --- Clear top edge when it overlaps other panels ---
            .overlay(Divider(), alignment: .top)

            // --- Keep it above underlying content but still let translucency read ---
            .zIndex(1)

            Group {
                if collapsed { content.frame(maxHeight: 84) } else { content }
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

    private let bullet = " — "

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main line (compact)
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

            // Detail (only when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text(timestamp(entry.date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let job = entry.jobID, !job.isEmpty {
                            Text("JobID: \(job)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    if let name = entry.filename, !name.isEmpty {
                        Text("File: \(name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    if let long = entry.detail, !long.isEmpty {
                        ScrollView {
                            Text(long)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }

                    // Action buttons - show if we have ANY useful data
                    let hasLogURL = entry.logURL != nil
                    let hasDetail = entry.detail?.isEmpty == false
                    let hasJobID = entry.jobID?.isEmpty == false
                    
                    if hasLogURL || hasDetail || hasJobID {
                        HStack(spacing: 12) {
                            // Reveal Log button (for local encodes)
                            if let url = entry.logURL {
                                Button("Reveal Log") {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                            
                            // Copy Info button (always show if we have any detail)
                            if hasDetail || hasJobID {
                                Button("Copy Info") {
                                    let textToCopy = buildCopyText(from: entry)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(textToCopy, forType: .string)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .padding(.leading, 20)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    // MARK: helpers
    private func mainLine(_ e: AppLogEntry) -> String {
        if let fn = e.filename, !fn.isEmpty { return "\(prefix(for: e.level))\(e.message)\(bullet)\(fn)" }
        return "\(prefix(for: e.level))\(e.message)"
    }
    
    private func prefix(for level: LogLevel) -> String {
        switch level { case .info: return ""; case .warning: return "Warning: "; case .error: return "Error: " }
    }
    
    private func color(for level: LogLevel) -> Color {
        switch level { case .info: return Color.blue.opacity(0.9); case .warning: return Color.orange.opacity(0.9); case .error: return Color.red.opacity(0.9) }
    }
    
    private func timestamp(_ date: Date) -> String {
        let df = DateFormatter(); df.dateStyle = .none; df.timeStyle = .short; return df.string(from: date)
    }
    
    /// Build comprehensive text for copy-to-clipboard
    private func buildCopyText(from entry: AppLogEntry) -> String {
        var lines: [String] = []
        
        // Header
        lines.append("=== MrHEVC Message ===")
        lines.append("Level: \(entry.level.rawValue.capitalized)")
        lines.append("Message: \(entry.message)")
        
        if let filename = entry.filename, !filename.isEmpty {
            lines.append("File: \(filename)")
        }
        
        if let jobID = entry.jobID, !jobID.isEmpty {
            lines.append("Job ID: \(jobID)")
        }
        
        lines.append("Timestamp: \(DateFormatter.messageDetail.string(from: entry.date))")
        
        // Detail section
        if let detail = entry.detail, !detail.isEmpty {
            lines.append("")
            lines.append("=== Details ===")
            lines.append(detail)
        }
        
        // Log path
        if let logURL = entry.logURL {
            lines.append("")
            lines.append("=== Log File ===")
            lines.append(logURL.path)
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - DateFormatter Extension
extension DateFormatter {
    static let messageDetail: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
}
