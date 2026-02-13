// =============================
// File: UI_QueueRow.swift — AppCore boundary, self-contained helpers
// =============================
import SwiftUI
import AppKit
import AVFoundation

struct UI_QueueRow: View {
    @EnvironmentObject var state: AppState

    let item: MediaItem
    let suggested: URL

    // Optional external expansion control
    var isExpandedExternal: Bool? = nil
    var onToggleExpand: (() -> Void)? = nil

    // Optional external queue/delete handlers (parent overrides)
    var isQueuedExternal: Bool? = nil
    var onToggleQueued: ((Bool) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var localExpanded: Bool = false

    private let chevronIndent: CGFloat = 46
    private let text75 = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.75)

    private var isExpanded: Bool { isExpandedExternal ?? localExpanded }

    // Binding that reads from live state and writes via AppCore
    private var queuedBinding: Binding<Bool> {
        if let external = isQueuedExternal {
            return Binding(get: { external }, set: { newVal in onToggleQueued?(newVal) })
        }
        return Binding(
            get: { state.files.first(where: { $0.id == item.id })?.isChecked ?? false },
            set: { AppCore.shared.toggleQueued(id: item.id, isQueued: $0) }
        )
    }

    private var statusLabel: (String, Color) {
        switch item.status {
        case .encoding: return ("Encoding", .blue)
        case .blocked:  return ("Blocked",  .orange)
        case .done:     return ("Done",     .green)
        default:        return ("Queued",   .secondary)
        }
    }

    var body: some View {
        let final = item.finalOutputURL ?? suggested

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {

                // Header row: checkbox + chevron + filename
                HStack(spacing: 8) {
                    Toggle("", isOn: queuedBinding)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .offset(y: 1.5)
                        .help("Include this item when encoding")

                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            if let onToggleExpand { onToggleExpand() }
                            else { localExpanded.toggle() }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Hide details" : "Show details")

                    Text(item.url.lastPathComponent)
                        .foregroundColor(text75)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.url.path)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        if let onToggleExpand { onToggleExpand() }
                        else { localExpanded.toggle() }
                    }
                }

                // Destination link (allows choosing a custom path)
                CustomDestinationLink(item: item, suggestedURL: suggested, settings: state.settings)
                    .padding(.leading, chevronIndent)

                // Metadata spinner
                if item.isProcessingMetadata {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6).controlSize(.mini)
                        Text("Reading metadata...")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.leading, chevronIndent)
                }

                // Estimated or final size/time line
                if let secs = item.actualEncodeSeconds, secs.isFinite, secs > 0,
                   let outURL = item.finalOutputURL,
                   let finalBytes = fileSizeBytes(outURL) {
                    Text("Final Size: \(formatFileSize(finalBytes)) • Render Time: \(EncodeTimeEstimator.formatTime(secs))")
                        .font(.callout).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.leading, chevronIndent)
                } else {
                    Text(buildEstimateSummary(url: item.url, meta: item.meta, settings: state.settings))
                        .font(.callout).foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.leading, chevronIndent)
                }

                // Progress + ETA
                if item.status == .encoding {
                    HStack(spacing: 8) {
                        Group {
                            if let p = item.progress { ProgressView(value: p) }
                            else { ProgressView() }
                        }
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 220, minHeight: 8)

                        if let eta = perItemETA(item: item, settings: state.settings) {
                            Text("ETA: \(eta)")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 20)
                    .padding(.leading, chevronIndent)
                }

                // Details
                if isExpanded {
                    if let src = makeSrcLine(url: item.url, meta: item.meta) {
                        Text("SRC: \(src)")
                            .font(.caption).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .padding(.leading, chevronIndent)
                            .transition(.opacity)
                    }
                    if let dst = makeDstTechnicalSpecs(url: item.url, meta: item.meta, settings: state.settings) {
                        Text("DST: \(dst)")
                            .font(.caption).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .padding(.leading, chevronIndent)
                            .transition(.opacity)
                    }
                    if item.status == .blocked, let r = item.statusReason {
                        Text(r)
                            .font(.caption).foregroundColor(text75)
                            .lineLimit(2)
                            .padding(.leading, chevronIndent)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.vertical, 5)

            Spacer()

            // Right-side actions
            HStack(spacing: 10) {
                if item.status == .encoding {
                    Button {
                        AppCore.shared.cancelAllEncoding()
                    } label: {
                        Text("Cancel").font(.callout).bold()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .keyboardShortcut(.cancelAction)
                    .help("Cancel current encodes")
                } else {
                    Text(statusLabel.0)
                        .font(.caption)
                        .foregroundColor(statusLabel.1)
                        .opacity(item.status == .done ? 0.0 : 1.0)

                    Button {
                        if let onDelete { onDelete() }
                        else { AppCore.shared.remove(id: item.id) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from queue")
                    .disabled(item.status == .encoding)
                }
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([final])
            }
            .disabled(!(item.status == .done))
        }
    }

    // MARK: - Helpers (local to this file)

    private func nclcDisplayNow(meta: MediaMetadata) -> String? {
        let label = state.settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    private func makeSrcLine(url: URL, meta: MediaMetadata) -> String? {
        var parts: [String] = []
        if meta.durationSeconds > 0 {
            let mins = Int(meta.durationSeconds / 60)
            let secs = Int(meta.durationSeconds.truncatingRemainder(dividingBy: 60))
            parts.append("\(mins):\(String(format: "%02d", secs))")
        }
        if let fps = meta.nominalFPS, fps > 0 {
            parts.append("\(String(format: "%.2f", fps)) fps")
        }
        // Add filename extension for clarity
        parts.append(url.pathExtension.uppercased())
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func makeDstTechnicalSpecs(url: URL, meta: MediaMetadata, settings: Settings) -> String? {
        if let e = OutputEstimator.estimate(url: url, meta: meta, settings: settings) {
            let nclc = nclcDisplayNow(meta: meta)
            let mb = e.estBytes / (1024.0 * 1024.0)
            var parts: [String] = []
            parts.append("\(e.outW)×\(e.outH)")
            parts.append("\(Int(round(e.fps))) fps")
            parts.append(EncodeTimeEstimator.formatTime(e.secs))
            if let n = nclc { parts.append(n) }
            parts.append(String(format: "%.1f MB est.", mb))
            return parts.joined(separator: " • ")
        }
        return nil
    }

    private func buildEstimateSummary(url: URL, meta: MediaMetadata, settings: Settings) -> String {
        if let dst = makeDstTechnicalSpecs(url: url, meta: meta, settings: settings) {
            return dst
        }
        return "Calculating estimates..."
    }

    private func perItemETA(item: MediaItem, settings: Settings) -> String? {
        guard let p = item.progress, p > 0, p < 1 else { return nil }
        let total = EncodeTimeEstimator.estimateSeconds(
            url: item.url,
            meta: item.meta,
            settings: settings,
            runMode: .localFFmpeg
        ) ?? 0
        guard total > 0 else { return nil }
        let remaining = total * (1 - p)
        return EncodeTimeEstimator.formatTime(remaining)
    }

    private func fileSizeBytes(_ url: URL) -> Int64? {
        do {
            let rv = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
            if let t = rv.totalFileAllocatedSize { return Int64(t) }
            if let a = rv.fileAllocatedSize { return Int64(a) }
            if let s = rv.fileSize { return Int64(s) }
        } catch { }
        return nil
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        f.includesUnit = true
        return f.string(fromByteCount: bytes)
    }
}

// MARK: - Destination link

private struct CustomDestinationLink: View {
    @EnvironmentObject var state: AppState
    let item: MediaItem
    let suggestedURL: URL
    let settings: Settings
    @State private var hovering = false

    private var finalURL: URL { item.finalOutputURL ?? suggestedURL }
    private var isEditable: Bool {
        // Allow edit when not encoding
        item.status != .encoding
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Save to:")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                if isEditable { showCustomPathDialog() }
            } label: {
                Text(finalURL.path)
                    .font(.caption)
                    .foregroundColor(isEditable ? .accentColor : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .underline(hovering && isEditable)
            }
            .buttonStyle(.plain)
            .help(isEditable ? "Click to choose a custom destination" : "Destination is locked while encoding")
            .onHover { hovering = $0 }
        }
    }

    private func showCustomPathDialog() {
        let panel = NSSavePanel()
        panel.title = "Choose Destination"
        panel.message = "Choose where to save the encoded file"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = finalURL.lastPathComponent
        panel.directoryURL = finalURL.deletingLastPathComponent()
        let ext = item.url.pathExtension
        if !ext.isEmpty {
            panel.allowedFileTypes = [ext]
        }

        panel.begin { response in
            guard response == .OK, let newURL = panel.url else { return }

            // Remote path safety check
            if settings.runMode == .remoteDeadline {
                let check = EncodeRemote.isInputPathAcceptableForFarm(newURL)
                if !check.ok {
                    let alert = NSAlert()
                    alert.messageText = "Invalid Destination Path"
                    alert.informativeText = check.reason ?? "The selected destination is not accessible to the render farm. Please choose a location on a shared network volume (e.g., /Volumes/Share/...)."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) }
                    else { alert.runModal() }

                    AppCore.shared.appendLog(level: .warning,
                                             "Custom destination blocked for remote encoding",
                                             filename: item.url.lastPathComponent,
                                             code: .farmPath,
                                             originKey: "custom-destination-farm-path",
                                             detail: "Path: \(newURL.path)\nReason: \(check.reason ?? "Not accessible to render farm")")
                    return
                }
            }

            // Commit via AppCore boundary
            AppCore.shared.setCustomDestination(id: item.id, newURL)
            AppCore.shared.appendLog(level: .info,
                                     "Custom destination set",
                                     filename: item.url.lastPathComponent,
                                     detail: "Will save to: \(newURL.path)")
        }
    }
}
