//
//  UI_MessageArea.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/16/25.
//

//
// MARK: - UI_MessageArea.swift (Always-available Copy + Visual Feedback)
//

import SwiftUI
import AppKit

struct UI_MessageArea: View {
    
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    // MARK: Copy feedback state
    @State private var copiedEntryID: UUID?

    // MARK: Environment
    @EnvironmentObject var state: AppState

    // MARK: Expansion state
    @State private var expanded: Set<UUID> = []

    // MARK: Messages
    private var messagesToShow: [AppLogEntry] {
        switch presentation {
        case .footer:
            // newest first, last 3
            return Array(state.uiMessages.suffix(3)).reversed()

        case .window:
            // show everything in-order (oldest -> newest)
            return state.uiMessages
        }
    }
    
    enum Presentation {
        case footer   // existing behavior (recent, bottom-ish)
        case window   // full log, top-left, tailing
    }

    let presentation: Presentation

    init(presentation: Presentation = .footer) {
        self.presentation = presentation
    }

    // MARK: Body
    var body: some View {
        if messagesToShow.isEmpty {
            EmptyView()
        } else {
            switch presentation {
            case .footer:
                footerBody

            case .window:
                windowBody
            }
        }
    }
    
    // MARK: - Footer presentation (existing behavior)
    private var footerBody: some View {
        let latestID = messagesToShow.first?.id

        let content = VStack(alignment: .leading, spacing: 6) {
            ForEach(messagesToShow) { message in
                UI_MessageRowCompact(
                    entry: message,
                    isExpanded: expanded.contains(message.id),
                    isCopied: copiedEntryID == message.id,
                    onToggle: { toggle(message.id) },
                    onCopy: { copyToPasteboard(buildCopyText(from: message), entryID: message.id) },
                    onRevealLog: {
                        if let url = message.logURL {
                            #if os(macOS)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                            #endif
                        }
                    }
                )
                .opacity(message.id == latestID ? 1.0 : 0.6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(C.bgPanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(C.strokeSubtle, lineWidth: 1)
        )

        // Preserve your original footer sizing/anchoring
        return Group {
            content
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .padding(.bottom, StyleConstants.Spacing.messageBottomMargin)
    }

    // MARK: - Window presentation (top-left, scrollable, tailing)
    private var windowBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(messagesToShow) { message in
                        UI_MessageRowCompact(
                            entry: message,
                            isExpanded: expanded.contains(message.id),
                            isCopied: copiedEntryID == message.id,
                            onToggle: { toggle(message.id) },
                            onCopy: { copyToPasteboard(buildCopyText(from: message), entryID: message.id) },
                            onRevealLog: {
                                if let url = message.logURL {
                                    #if os(macOS)
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                    #endif
                                }
                            }
                        )
                        .id(message.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            // Tail the log as new messages arrive (auto-scroll to newest)
            .onAppear {
                scrollToBottom(proxy)
            }
            .onChange(of: state.uiMessages.count) { _ in
                scrollToBottom(proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(C.bgApp)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastID = state.uiMessages.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }



    // MARK: Helpers

    private func toggle(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expanded.contains(id) { expanded.remove(id) }
            else { expanded.insert(id) }
        }
    }

    private func copyToPasteboard(_ text: String, entryID: UUID) {
        #if os(macOS)
        let p = NSPasteboard.general
        p.clearContents()
        p.setString(text, forType: .string)
        #endif
        withAnimation(.easeInOut(duration: 0.15)) {
            copiedEntryID = entryID
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + StyleConstants.Motion.copiedToastDuration) {
            withAnimation(.easeInOut(duration: 0.25)) {
                if copiedEntryID == entryID { copiedEntryID = nil }
            }
        }
    }

    private func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    /// Compose a full, human-readable block for Copy
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
            parts.append("Details:\n\(detail)")
        }
        return parts.joined(separator: "\n")
    }
}


// MARK: - Message Row (Compact + Expandable)

private struct UI_MessageRowCompact: View {
    let entry: AppLogEntry
    let isExpanded: Bool
    let isCopied: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onRevealLog: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    private let bullet = " • "

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // COLLAPSED LINE
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // Expand/collapse chevron
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(C.textSecondary)
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

                // Always-available Copy (collapsed too)
                Button("Copy") { onCopy() }
                    .buttonStyle(.borderless)
                    .font(.caption)

                if isCopied {
                    Text("Copied")
                        .font(.caption)
                        .foregroundColor(C.textSecondary)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }

            // EXPANDED DETAILS
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Timestamp and Job ID
                    HStack(spacing: 16) {
                        Label(timestamp(entry.date), systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(C.textSecondary)

                        if let job = entry.jobID, !job.isEmpty {
                            Label("Job: \(job)", systemImage: "number")
                                .font(.caption)
                                .foregroundColor(C.textSecondary)
                                .textSelection(.enabled)
                        }

                        Spacer()
                    }

                    // Filename
                    if let name = entry.filename, !name.isEmpty {
                        Label("File: \(name)", systemImage: "doc")
                            .font(.caption)
                            .foregroundColor(C.textSecondary)
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
                        .background(C.bgPanel)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(C.strokeSubtle, lineWidth: 1)
                        )
                    }

                    // Actions row (standardized)
                    HStack(spacing: 12) {
                        Button("Show Log") { onRevealLog() }
                            .buttonStyle(.link)
                            .font(.caption)
                            .disabled(entry.logURL == nil)
                            .help(entry.logURL == nil ? "No log file available" : "Reveal log in Finder")

                        Button("Copy Details") { onCopy() }
                            .buttonStyle(.link)
                            .font(.caption)

                        if isCopied {
                            Text("Copied")
                                .font(.caption)
                                .foregroundColor(C.textSecondary)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }

                        Spacer()
                    }
                }
                .padding(.leading, 22) // align with message text
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: isCopied)
    }

    // MARK: - Row helpers

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
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}
