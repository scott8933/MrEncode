//
// MARK: - UI_Queue.swift — Restored drag/drop + AppCore boundary
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import AppKit

struct UI_Queue: View {
    @EnvironmentObject var state: AppState

    // Back-compat: allow old call sites, but also support UI_Queue()
    let fixedHeight: CGFloat?
    let isAutoMode: Bool
    let showInternalHandle: Bool

    init(
        fixedHeight: CGFloat? = nil,
        isAutoMode: Bool = false,
        showInternalHandle: Bool = true
    ) {
        self.fixedHeight = fixedHeight
        self.isAutoMode = isAutoMode
        self.showInternalHandle = showInternalHandle
    }

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: AppColors.panelSpacing) {

            // Header
            QueueHeader()
                .padding(.horizontal, AppColors.panelPadding)

            // Queue list (rows)
            ZStack {
                if state.files.isEmpty {
                    EmptyQueueView()
                        .padding(.vertical, 20)
                        .padding(.horizontal, AppColors.panelPadding)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(state.files, id: \.id) { item in
                                UI_QueueRow(
                                    item: item,
                                    suggested: suggestedURL(for: item),
                                    isQueuedExternal: item.isChecked,
                                    onToggleQueued: { newVal in
                                        AppCore.shared.toggleQueued(id: item.id, isQueued: newVal)
                                    },
                                    onDelete: {
                                        AppCore.shared.remove(id: item.id)
                                    }
                                )
                                .environmentObject(state)
                                .padding(.horizontal, AppColors.panelPadding)

                                Divider().padding(.leading, AppColors.panelPadding + 44)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: fixedHeight) // honored when provided
            .background(
                RoundedRectangle(cornerRadius: AppColors.panelCornerRadius)
                    .strokeBorder(isTargeted ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.15), lineWidth: isTargeted ? 2 : 1)
                    .background(
                        RoundedRectangle(cornerRadius: AppColors.panelCornerRadius)
                            .fill(isTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppColors.panelCornerRadius))

            // Drag & Drop
            .onDrop(of: [UTType.fileURL, UTType.movie, UTType.quickTimeMovie],
                    isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }

            // Footer controls
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    AppCore.shared.cancelAllEncoding()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(!state.files.contains { $0.status == .encoding })

                Button("Encode") {
                    let chosen = state.files.filter { $0.isChecked && $0.status == .queued }
                    if chosen.isEmpty {
                        AppCore.shared.appendLog(level: .warning, "No files ready to encode")
                        return
                    }
                    state.submit(items: chosen) // forwards into core services
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!state.files.contains { $0.isChecked && $0.status == .queued })
            }
            .padding(.horizontal, AppColors.panelPadding)
            .padding(.vertical, 8)
        }

        // Alerts used by drop processing
        .alert(AppCore.shared.folderAlertTitle, isPresented: Binding(
            get: { AppCore.shared.showFolderAlert },
            set: { AppCore.shared.showFolderAlert = $0 }
        )) {
            Button("OK") { AppCore.shared.showFolderAlert = false }
        } message: {
            Text(AppCore.shared.folderAlertMessage)
        }
        .alert(
            Text("Add Many Files?"),
            isPresented: Binding(
                get: { AppCore.shared.showAmountConfirm },
                set: { AppCore.shared.showAmountConfirm = $0 }
            )
        ) {
            Button("Cancel") {
                AppCore.shared.pendingAddAfterConfirm = []
                AppCore.shared.showAmountConfirm = false
            }
            Button("Add All") {
                // ✅ boundary-safe: use state.addFiles (forwards to AppCore)
                state.addFiles(AppCore.shared.pendingAddAfterConfirm)
                AppCore.shared.pendingAddAfterConfirm = []
                AppCore.shared.showAmountConfirm = false
            }
        } message: {
            Text("Large add detected. For safety, folders are not scanned recursively.")
        }
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        var rawURLs = Set<URL>()
        let group = DispatchGroup()

        func addURL(_ url: URL?) {
            guard let url = url, url.isFileURL else { return }
            rawURLs.insert(url.standardizedFileURL)
        }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            group.enter()
            provider.loadObject(ofClass: NSURL.self) { obj, _ in
                defer { group.leave() }
                addURL((obj as? NSURL) as URL?)
            }
        }

        group.notify(queue: .main) {
            guard !rawURLs.isEmpty else { return }

            // Process dropped URLs on a background queue
            DispatchQueue.global(qos: .userInitiated).async {
                var topLevelMovieFiles = Set<URL>()
                var sawSubfolders: [String] = []
                var rejected: [String] = []
                var allWarnings: [String] = []

                let fm = FileManager.default

                for url in rawURLs {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        // Folder: add only top-level .mov (no recursion)
                        if let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [.skipsHiddenFiles]) {
                            for child in children {
                                let rv = try? child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                                if rv?.isDirectory == true {
                                    sawSubfolders.append(child.lastPathComponent)
                                } else if rv?.isRegularFile == true {
                                    if isAllowedQuickTime(child) {
                                        topLevelMovieFiles.insert(child.standardizedFileURL)
                                    }
                                }
                            }
                        }
                    } else {
                        // Single file
                        if isAllowedQuickTime(url) {
                            topLevelMovieFiles.insert(url.standardizedFileURL)
                        } else {
                            rejected.append(url.lastPathComponent)
                        }
                    }
                }

                // Build warnings
                if !rejected.isEmpty {
                    let fileList = rejected.count > 5
                        ? Array(rejected.prefix(5)).joined(separator: ", ") + ", and \(rejected.count - 5) more"
                        : rejected.joined(separator: ", ")
                    allWarnings.append("Non-QuickTime files skipped: \(fileList)")
                }
                if !sawSubfolders.isEmpty {
                    let folderList = sawSubfolders.count > 5
                        ? Array(sawSubfolders.prefix(5)).joined(separator: ", ") + ", and \(sawSubfolders.count - 5) more"
                        : sawSubfolders.joined(separator: ", ")
                    allWarnings.append("Subfolders not scanned: \(folderList)")
                }

                // De-dupe against existing queue
                let existing = Set(state.files.map { $0.url.standardizedFileURL })
                let candidates = Array(topLevelMovieFiles.subtracting(existing))

                DispatchQueue.main.async {
                    // Surface warnings (single alert aggregates both categories)
                    if !allWarnings.isEmpty {
                        AppCore.shared.folderAlertTitle = "Drop Processing"
                        AppCore.shared.folderAlertMessage = allWarnings.joined(separator: "\n\n")
                        AppCore.shared.showFolderAlert = true
                    }

                    guard !candidates.isEmpty else { return }

                    // Large add confirmation
                    if candidates.count > 25 {
                        AppCore.shared.pendingAddAfterConfirm = candidates
                        AppCore.shared.showAmountConfirm = true
                    } else {
                        // Add immediately
                        state.addFiles(candidates)

                        // Post-add sanity warnings for evenization
                        for url in candidates {
                            sanityCheckEvenize(for: url, settings: state.settings)
                        }

                        // Auto-encode if requested
                        if state.settings.autoEncodeOnDrop {
                            let itemsToSubmit = state.files.filter { $0.status == .queued && $0.isChecked }
                            state.submit(items: itemsToSubmit)
                        }
                    }
                }
            }
        }
        return accepted
    }

    // Warn if output will be evenized (post-add hint)
    private func sanityCheckEvenize(for url: URL, settings: Settings) {
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return }
        let n = track.naturalSize.applying(track.preferredTransform)
        let srcW = Int(abs(n.width).rounded())
        let srcH = Int(abs(n.height).rounded())

        // Scale factor from settings
        let factor = settings.scale.factor
        let rawW = Int(Double(srcW) * factor)
        let rawH = Int(Double(srcH) * factor)
        let evenW = (rawW / 2) * 2
        let evenH = (rawH / 2) * 2

        if rawW != evenW || rawH != evenH {
            AppCore.shared.appendLog(
                level: .warning,
                "Non-even dims will be evenized: \(rawW)×\(rawH) → \(evenW)×\(evenH)",
                filename: url.lastPathComponent
            )
        } else if (srcW % 2 != 0 || srcH % 2 != 0) && factor == 1.0 {
            AppCore.shared.appendLog(
                level: .warning,
                "Source has odd dims; output will be \(evenW)×\(evenH)",
                filename: url.lastPathComponent
            )
        }
    }

    private func suggestedURL(for item: MediaItem) -> URL {
        if let custom = item.finalOutputURL { return custom }
        return OutputNamer.suggestedOutputURL(for: item.url, settings: state.settings)
    }
}

// MARK: - Subviews

private struct QueueHeader: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: AppColors.controlSpacing) {
            Text("Queue")
                .font(.headline)
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
        }
        .padding(.top, 4)
    }
}

private struct EmptyQueueView: View {
    var body: some View {
        VStack(spacing: AppColors.panelSpacing) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 28))
                .opacity(0.6)
            Text("Drop QuickTime files or Folder here")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}


// Acceptable input containers for drop (QuickTime + common MPEG-4)
private func isAllowedQuickTime(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    // Prefer UTType when we can resolve it
    if let ut = UTType(filenameExtension: ext) {
        // Allow native QuickTime .mov and MPEG-4 movie types
        if ut == .quickTimeMovie || ut == .mpeg4Movie { return true }
        // Fallback: any "movie" that is one of our known extensions
        if ut.conforms(to: .movie) && (ext == "mov" || ext == "mp4" || ext == "m4v" || ext == "qt") {
            return true
        }
        return false
    }
    // If UTType can’t resolve, fall back to extension check
    return ext == "mov" || ext == "mp4" || ext == "m4v" || ext == "qt"
}
