//
// MARK: - UI_MessageArea.swift (Revised - Clean Non-Overlay Design)
//

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
                ForEach(recent) { message in
                    UI_MessageRowCompact(
                        entry: message,
                        isExpanded: expanded.contains(message.id),
                        onToggle: { toggle(message.id) }
                    )
                    .opacity(message.id == latestID ? 1.0 : 0.6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            // Clean card-style background (no more translucency tricks)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            Group {
                if collapsed {
                    content.frame(maxHeight: 60)
                } else {
                    content
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expanded.contains(id) {
                expanded.remove(id)
            } else {
                expanded.insert(id)
            }
        }
    }
}

// MARK: - Message Row (Improved)

private struct UI_MessageRowCompact: View {
    let entry: AppLogEntry
    let isExpanded: Bool
    let onToggle: () -> Void

    private let bullet = " • "

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Main line (compact) - improved layout
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // Expand/collapse chevron
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Status dot
                Circle()
                    .fill(color(for: entry.level))
                    .frame(width: 7, height: 7)

                // Message text
                Text(mainLine(entry))
                    .font(.callout)
                    .foregroundColor(.primary)
                    .lineLimit(isExpanded ? nil : 2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }

            // Detail section (only when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Timestamp and Job ID
                    HStack(spacing: 16) {
                        Label(timestamp(entry.date), systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let job = entry.jobID, !job.isEmpty {
                            Label("Job: \(job)", systemImage: "number")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        
                        Spacer()
                    }

                    // Filename
                    if let name = entry.filename, !name.isEmpty {
                        Label("File: \(name)", systemImage: "doc")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    // Detailed message (scrollable if long)
                    if let detail = entry.detail, !detail.isEmpty {
                        ScrollView {
                            Text(detail)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                    }

                    // Action buttons - only show if we have useful actions
                    let hasLogURL = entry.logURL != nil
                    let hasDetail = entry.detail?.isEmpty == false
                    let hasJobID = entry.jobID?.isEmpty == false
                    
                    if hasLogURL || hasDetail || hasJobID {
                        HStack(spacing: 12) {
                            // Reveal Log button (for local encodes)
                            if let url = entry.logURL {
                                Button("Show Log") {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                            
                            // Copy Info button
                            if hasDetail || hasJobID {
                                Button("Copy Details") {
                                    let textToCopy = buildCopyText(from: entry)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(textToCopy, forType: .string)
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                            
                            Spacer()
                        }
                    }
                }
                .padding(.leading, 22) // Align with message text
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: - Helper Methods
    
    private func mainLine(_ e: AppLogEntry) -> String {
        let prefix = prefix(for: e.level)
        if let fn = e.filename, !fn.isEmpty {
            return "\(prefix)\(e.message)\(bullet)\(fn)"
        }
        return "\(prefix)\(e.message)"
    }
    
    private func prefix(for level: LogLevel) -> String {
        switch level {
        case .info: return ""
        case .warning: return "Warning: "
        case .error: return "Error: "
        }
    }
    
    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return Color.blue.opacity(0.8)
        case .warning: return Color.orange.opacity(0.8)
        case .error: return Color.red.opacity(0.8)
        }
    }
    
    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func buildCopyText(from entry: AppLogEntry) -> String {
        var parts: [String] = []
        
        parts.append("Level: \(entry.level)")
        parts.append("Time: \(timestamp(entry.date))")
        parts.append("Message: \(entry.message)")
        
        if let filename = entry.filename, !filename.isEmpty {
            parts.append("File: \(filename)")
        }
        
        if let jobID = entry.jobID, !jobID.isEmpty {
            parts.append("Job ID: \(jobID)")
        }
        
        if let detail = entry.detail, !detail.isEmpty {
            parts.append("Details: \(detail)")
        }
        
        return parts.joined(separator: "\n")
    }
}
