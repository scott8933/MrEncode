// =============================
// File: UI_Queue.swift (Simplified version using existing AppState)
// =============================

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import AppKit

// Shared drop types for consistency
fileprivate let queueDropTypes: [UTType] = [.fileURL, .movie, .quickTimeMovie]

// MARK: - Main Queue View

struct UI_Queue: View {
    @EnvironmentObject var state: AppState

    // UI state only
    @State private var isTargeted = false
    @State private var isListTargeted = false
    private var isDropActive: Bool { isTargeted || isListTargeted }

    // Local alert state (until AppCore integration is complete)
    @State private var showFolderAlert = false
    @State private var folderAlertMessage = ""
    @State private var pendingAddAfterConfirm: [URL] = []
    @State private var showAmountConfirm = false

    let fixedHeight: CGFloat?
    let isAutoMode: Bool
    @State private var height: CGFloat = 240

    private enum C {
        static let corner: CGFloat = 8
        static let minH: CGFloat = 140
        static let maxH: CGFloat = 700
        static let pad: CGFloat = 12
        static let padding: CGFloat = 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: C.padding) {
            if !isAutoMode {
                QueueHeader()
            }

            // Unified drop zone with highlighting
            ZStack {
                RoundedRectangle(cornerRadius: C.corner)
                    .fill(Color(NSColor.windowBackgroundColor))

                content
                    .padding(C.pad)
            }
            .clipShape(RoundedRectangle(cornerRadius: C.corner))
            .frame(
                minHeight: C.minH,
                idealHeight: isAutoMode ? nil : height,
                maxHeight: isAutoMode ? .infinity : height
            )
            .overlay(
                RoundedRectangle(cornerRadius: C.corner)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: C.corner)
                    .stroke(isDropActive ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 2)
            )
            .onDrop(of: queueDropTypes, isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
            .overlay(alignment: .bottom) {
                if !isAutoMode {
                    ResizeHandle(height: $height, minHeight: C.minH, maxHeight: C.maxH)
                        .padding(.bottom, 6)
                }
            }
        }
        // Local alert handling (simplified for now)
        .alert("Folder Processing", isPresented: $showFolderAlert) {
            Button("OK") { showFolderAlert = false }
        } message: {
            Text(folderAlertMessage)
        }
        .alert("Add \(pendingAddAfterConfirm.count) files to the queue?", isPresented: $showAmountConfirm) {
            Button("Cancel") {
                pendingAddAfterConfirm = []
                showAmountConfirm = false
            }
            Button("Add All") {
                state.addFiles(pendingAddAfterConfirm)
                pendingAddAfterConfirm = []
                showAmountConfirm = false
            }
        } message: {
            Text("Large add detected. For safety, folders are not scanned recursively.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.files.isEmpty {
            EmptyQueueView()
        } else {
            QueueList(isListTargeted: $isListTargeted)
        }
    }

    // Drag-drop handler - processes files and adds to queue
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        var rawURLs = Set<URL>()
        let group = DispatchGroup()

        // Extract URLs from providers
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            group.enter()
            provider.loadObject(ofClass: NSURL.self) { obj, _ in
                defer { group.leave() }
                if let url = (obj as? NSURL) as URL?, url.isFileURL {
                    rawURLs.insert(url.standardizedFileURL)
                }
            }
        }

        // Process dropped files
        group.notify(queue: .global(qos: .userInitiated)) {
            processDroppedFiles(rawURLs)
        }

        return accepted
    }
    
    // Process dropped files and folders
    private func processDroppedFiles(_ rawURLs: Set<URL>) {
        let fm = FileManager.default
        var topLevelMovieFiles = Set<URL>()
        var rejected: [String] = []
        var sawSubfolders: [String] = []

        for url in rawURLs {
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            guard exists else { continue }

            if isDir.boolValue {
                // One-level scan
                let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
                if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
                    for child in contents {
                        if let rv = try? child.resourceValues(forKeys: Set(keys)) {
                            if rv.isDirectory == true {
                                sawSubfolders.append(child.lastPathComponent)
                            } else if rv.isRegularFile == true {
                                if child.pathExtension.lowercased() == "mov" {
                                    topLevelMovieFiles.insert(child.standardizedFileURL)
                                }
                            }
                        }
                    }
                }
            } else {
                if url.pathExtension.lowercased() == "mov" {
                    topLevelMovieFiles.insert(url.standardizedFileURL)
                } else {
                    rejected.append(url.lastPathComponent)
                }
            }
        }

        DispatchQueue.main.async {
            var alertParts: [String] = []

            if !rejected.isEmpty {
                let fileList = rejected.count > 5
                ? Array(rejected.prefix(5)).joined(separator: ", ") + ", and \(rejected.count - 5) more"
                : rejected.joined(separator: ", ")
                alertParts.append("Non-QuickTime files skipped: \(fileList)")
            }

            if !sawSubfolders.isEmpty {
                let folderList = sawSubfolders.count > 5
                ? Array(sawSubfolders.prefix(5)).joined(separator: ", ") + ", and \(sawSubfolders.count - 5) more"
                : sawSubfolders.joined(separator: ", ")
                alertParts.append("Subfolders not scanned: \(folderList)")
            }

            let existing = Set(state.files.map { $0.url.standardizedFileURL })
            let candidates = Array(topLevelMovieFiles.subtracting(existing))
            let wasFolder = rawURLs.contains { url in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                return isDir.boolValue
            }

            if candidates.isEmpty && wasFolder {
                if topLevelMovieFiles.isEmpty {
                    alertParts.append("No QuickTime (.mov) files found in the dropped folder(s)")
                } else {
                    alertParts.append("All QuickTime files are already in the queue")
                }
            }

            if !alertParts.isEmpty {
                folderAlertMessage = alertParts.joined(separator: "\n\n")
                showFolderAlert = true
            }

            guard !candidates.isEmpty else { return }

            // Add sanity checks
            for url in candidates {
                sanityCheckEvenize(for: url, settings: state.settings)
            }

            if candidates.count > 25 {
                pendingAddAfterConfirm = candidates
                showAmountConfirm = true
            } else {
                state.addFiles(candidates)
            }
        }
    }
}

// MARK: - Queue Header

private struct QueueHeader: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        HStack {
            Text("Queue").font(.headline)
            Spacer()
            if !state.selectedIDs.isEmpty {
                Text("\(state.selectedIDs.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button("Clear All") {
                state.clearAllNonEncoding()
                state.selectedIDs.removeAll()
            }
            .disabled(state.files.filter { $0.status != .encoding }.isEmpty)
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Queue List

private struct QueueList: View {
    @EnvironmentObject var state: AppState
    @Binding var isListTargeted: Bool
    @State private var expandedRowIDs: Set<UUID> = []

    private func suggestedURL(for item: MediaItem) -> URL {
        item.finalOutputURL ?? OutputNamer.suggestedOutputURL(for: item.url, settings: state.settings)
    }

    var body: some View {
        List(state.files, id: \.id) { item in
            QueueRowView(
                item: item,
                suggested: suggestedURL(for: item),
                isExpanded: expandedRowIDs.contains(item.id),
                onToggleExpand: {
                    if expandedRowIDs.contains(item.id) {
                        expandedRowIDs.remove(item.id)
                    } else {
                        expandedRowIDs.insert(item.id)
                    }
                },
                onToggleQueued: { newVal in
                    guard item.status != .encoding else { return }
                    // Use AppState.shared pattern like other parts of codebase
                    if let shared = AppState.shared,
                       let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                        shared.files[idx].isChecked = newVal
                    }
                },
                onDelete: {
                    state.removeItems(withIDs: [item.id])
                    expandedRowIDs.remove(item.id)
                }
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        }
        .listStyle(.plain)
        .onDrop(of: queueDropTypes, isTargeted: $isListTargeted) { providers in
            // Delegate to parent's drop handler
            return false // Let the parent handle it
        }
        .environment(\.defaultMinListRowHeight, 28)
    }
}

// MARK: - Queue Row View

private struct QueueRowView: View {
    @EnvironmentObject var state: AppState
    
    let item: MediaItem
    let suggested: URL
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggleQueued: (Bool) -> Void
    let onDelete: () -> Void

    private let chevronIndent: CGFloat = 20
    private let text75 = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.75)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // 1) Checkbox
            Button {
                onToggleQueued(!item.isChecked)
            } label: {
                Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundColor(item.isChecked ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(item.status == .blocked || item.status == .encoding)

            VStack(alignment: .leading, spacing: 4) {
                // 2) Header: chevron + filename
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            onToggleExpand()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 14, height: 14, alignment: .center)
                    }
                    .buttonStyle(.plain)

                    Text(item.url.lastPathComponent)
                        .foregroundColor(text75)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                // 3) Output path (clickable)
                OutputPathLink(item: item, suggested: suggested)
                    .padding(.leading, chevronIndent)
                
                // 4) Processing indicator
                if item.isProcessingMetadata {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .controlSize(.mini)
                        Text("Reading metadata...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, chevronIndent)
                }
                
                // 5) Size/time estimates
                EstimatesView(item: item)
                    .padding(.leading, chevronIndent)

                // 6) Progress bar (encoding only)
                if item.status == .encoding {
                    ProgressBarView(item: item)
                        .padding(.leading, chevronIndent)
                }

                // 7) Expanded details
                if isExpanded {
                    ExpandedDetails(item: item)
                        .padding(.leading, chevronIndent)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 5)

            Spacer()

            // 8) Cancel/Delete button
            RightActionButton(
                item: item,
                onCancel: {
                    AppState.shared?.cancelEncoding(itemID: item.id)
                },
                onDelete: onDelete
            )
        }
    }
}

// MARK: - Supporting Views

private struct OutputPathLink: View {
    @EnvironmentObject var state: AppState
    let item: MediaItem
    let suggested: URL
    
    var body: some View {
        let final = item.finalOutputURL ?? suggested
        
        Button {
            showCustomDestination()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(final.lastPathComponent)
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .buttonStyle(.plain)
        .disabled(item.status == .encoding)
    }
    
    private func showCustomDestination() {
        let panel = NSSavePanel()
        panel.title = "Choose Destination"
        panel.nameFieldStringValue = (item.finalOutputURL ?? suggested).lastPathComponent
        panel.allowedContentTypes = [.quickTimeMovie]
        
        panel.begin { response in
            guard response == .OK, let newURL = panel.url else { return }
            
            // Validate path for remote encoding
            if state.settings.runMode == .remoteDeadline {
                let pathCheck = EncodeRemote.isInputPathAcceptableForFarm(newURL)
                if !pathCheck.ok {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Remote Encoding Path Issue"
                        alert.informativeText = pathCheck.reason ?? "Path not accessible to render farm"
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                    return
                }
            }
            
            // Update via AppState.shared pattern
            DispatchQueue.main.async {
                if let shared = AppState.shared,
                   let idx = shared.files.firstIndex(where: { $0.id == item.id }) {
                    shared.files[idx].finalOutputURL = newURL
                }
            }
        }
    }
}

private struct EstimatesView: View {
    @EnvironmentObject var state: AppState
    let item: MediaItem
    
    var body: some View {
        if let actualSecs = item.actualEncodeSeconds, actualSecs.isFinite, actualSecs > 0,
           let finalURL = item.finalOutputURL,
           let finalBytes = fileSizeBytes(finalURL) {
            // Final results
            Text("Final Size: \(formatFileSize(finalBytes)) • Render Time: \(EncodeTimeEstimator.formatTime(actualSecs))")
                .font(.callout)
                .foregroundColor(.secondary)
                .lineLimit(1)
        } else if item.isProcessingMetadata {
            Text("Calculating estimates...")
                .font(.callout)
                .foregroundColor(.secondary)
        } else {
            // Show estimates
            let summary = buildEstimateSummary(url: item.url, meta: item.meta, settings: state.settings)
            Text(summary)
                .font(.callout)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
    
    private func buildEstimateSummary(url: URL, meta: MediaMetadata, settings: Settings) -> String {
        var parts: [String] = []
        
        if let est = OutputEstimator.estimate(url: url, meta: meta, settings: settings) {
            let mb = est.estBytes / 1_000_000.0
            if mb >= 1000 {
                parts.append("Est. Size: \(String(format: "%.1f GB", mb / 1000.0))")
            } else {
                parts.append("Est. Size: \(String(format: "%.1f MB", mb))")
            }
        }
        
        if let wallTime = EncodeTimeEstimator.estimateSeconds(
            url: url, meta: meta, settings: settings, runMode: settings.runMode
        ), wallTime.isFinite, wallTime > 0 {
            parts.append("Est. Render Time: \(EncodeTimeEstimator.formatTime(wallTime))")
        }
        
        return parts.isEmpty ? "Estimating..." : parts.joined(separator: " • ")
    }
}

private struct ProgressBarView: View {
    let item: MediaItem
    
    var body: some View {
        HStack(spacing: 8) {
            if let progress = item.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            
            if let reason = item.statusReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if let eta = item.etaSeconds, eta.isFinite, eta > 0 {
                Text("ETA: \(EncodeTimeEstimator.formatTime(eta))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 20)
    }
}

private struct ExpandedDetails: View {
    let item: MediaItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let srcLine = item.cachedSrcLine {
                Text("SRC: \(srcLine)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if let dstLine = item.cachedDstLine {
                Text("DST: \(dstLine)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if item.status == .blocked, let reason = item.statusReason {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
    }
}

private struct RightActionButton: View {
    let item: MediaItem
    let onCancel: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        if item.status == .encoding {
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundColor(.orange)
        } else {
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(item.status == .encoding)
        }
    }
}

// MARK: - Empty State

private struct EmptyQueueView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 28))
                .opacity(0.6)
            Text("Drop QuickTime files or Folder here")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Resize Handle Component

private struct ResizeHandle: View {
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    @State private var hovering = false
    
    var body: some View {
        ZStack {
            Rectangle().fill(.clear).frame(height: 16).contentShape(Rectangle())
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(hovering ? 0.7 : 0.45))
                .frame(width: 64, height: 4)
        }
        .onHover { hover in
            hovering = hover
            if hover { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(DragGesture(minimumDistance: 1).onChanged { value in
            let newH = height + value.translation.height
            height = min(max(newH, minHeight), maxHeight)
        })
    }
}

// MARK: - Helper Functions

private func fileSizeBytes(_ url: URL) -> Int64? {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.size] as? Int64
    } catch {
        return nil
    }
}

private func formatFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useAll]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

/// Warn when the (scaled) output dims will be odd and need evenizing.
/// Also warn when the *source* is odd and scale is 1:1 (we'll evenize on encode).
private func sanityCheckEvenize(for url: URL, settings: Settings) {
    let asset = AVAsset(url: url)
    guard let v = asset.tracks(withMediaType: .video).first else { return }
    let natural = v.naturalSize
    let tx = v.preferredTransform
    // account for rotation
    let r = natural.applying(tx)
    let srcW = Int(abs(r.width).rounded())
    let srcH = Int(abs(r.height).rounded())
    guard srcW > 0, srcH > 0 else { return }

    let factor = settings.scale.factor
    let rawW = max(1, Int(round(Double(srcW) * factor)))
    let rawH = max(1, Int(round(Double(srcH) * factor)))
    let evenW = (rawW / 2) * 2
    let evenH = (rawH / 2) * 2

    if rawW != evenW || rawH != evenH {
        AppState.shared?.pushMessage(
            level: .warning,
            "Non-even dims will be evenized: \(rawW)×\(rawH) → \(evenW)×\(evenH)",
            filename: url.lastPathComponent
        )
    } else if (srcW % 2 != 0 || srcH % 2 != 0) && factor == 1.0 {
        AppState.shared?.pushMessage(
            level: .warning,
            "Source has odd dims; output will be \(evenW)×\(evenH)",
            filename: url.lastPathComponent
        )
    }
}
