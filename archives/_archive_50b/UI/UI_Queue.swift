//
//  UI_Queue.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/16/25.
//

// MARK: - UI_Queue.swift (Revised to source sizes/colors from AppColors and follow parent height)

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct UI_Queue: View {
    @EnvironmentObject var state: AppState
    @StateObject private var queueViewModel = QueueViewModel()

    let fixedHeight: CGFloat?
    let isAutoMode: Bool
    let showInternalHandle: Bool

    @State private var isTargeted = false

    init(fixedHeight: CGFloat? = nil, isAutoMode: Bool = false) {
        self.fixedHeight = fixedHeight
        self.isAutoMode = isAutoMode
        self.showInternalHandle = true
    }

    init(fixedHeight: CGFloat? = nil, isAutoMode: Bool = false, showInternalHandle: Bool) {
        self.fixedHeight = fixedHeight
        self.isAutoMode = isAutoMode
        self.showInternalHandle = showInternalHandle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StyleConstants.panelSpacing) {
            
            QueueHeader()
                .padding(.horizontal, StyleConstants.panelPadding)
                .padding(.top, StyleConstants.panelSpacing)
            
            ZStack(alignment: .top) {
                // Panel fill
                RoundedRectangle(cornerRadius: StyleConstants.panelCornerRadius)
                    .fill(StyleConstants.panelFill)

                // Panel stroke
                RoundedRectangle(cornerRadius: StyleConstants.panelCornerRadius)
                    .strokeBorder(
                        isTargeted
                            ? Color.accentColor.opacity(StyleConstants.strokeOpacityActive)
                            : Color.secondary.opacity(StyleConstants.strokeOpacityNormal),
                        lineWidth: isTargeted ? StyleConstants.activeBorderLineWidth : StyleConstants.borderLineWidth
                    )
                    .animation(.easeInOut(duration: StyleConstants.hoverAnimationDuration), value: isTargeted)

                // Content
                if state.files.isEmpty {
                    // Center empty-state vertically inside padded area
                    VStack {
                        Spacer()
                        EmptyQueueView()
                        Spacer()
                    }
                    .padding(StyleConstants.panelPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    // Pin list to top
                    ZStack(alignment: .top) {
                        QueueList()
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .padding(StyleConstants.panelPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .ifLet(fixedHeight) { view, h in
                view.frame(height: h, alignment: .top) // parent-controlled Queue height
            }
            .onDrop(of: [UTType.fileURL, UTType.movie, UTType.quickTimeMovie],
                    isTargeted: $isTargeted,
                    perform: handleDrop)
        }
        // Alerts (preserved)
        .alert(AppCore.shared.folderAlertTitle, isPresented: Binding(
            get: { AppCore.shared.showFolderAlert },
            set: { AppCore.shared.showFolderAlert = $0 }
        )) {
            Button("OK") { AppCore.shared.showFolderAlert = false }
        } message: {
            Text(AppCore.shared.folderAlertMessage)
        }
        .alert("Add \(AppCore.shared.pendingAddAfterConfirm.count) files to the queue?", isPresented: Binding(
            get: { AppCore.shared.showAmountConfirm },
            set: { AppCore.shared.showAmountConfirm = $0 }
        )) {
            Button("Cancel") {
                AppCore.shared.pendingAddAfterConfirm = []
                AppCore.shared.showAmountConfirm = false
            }
            Button("Add All") {
                // Add the candidates
                AppState.shared?.addFiles(AppCore.shared.pendingAddAfterConfirm)
                AppCore.shared.pendingAddAfterConfirm = []
                AppCore.shared.showAmountConfirm = false

                // ✅ NEW: kick off Auto-Encode after bulk add
                if let s = AppState.shared, s.settings.autoEncodeOnDrop {
                    s.submit()
                }
            }
        } message: {
            Text("Large add detected. For safety, folders are not scanned recursively.")
        }

    }


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

        let movieUTIs = [UTType.movie.identifier, UTType.quickTimeMovie.identifier]
        for provider in providers where movieUTIs.contains(where: { provider.hasItemConformingToTypeIdentifier($0) }) {
            accepted = true
            if provider.canLoadObject(ofClass: NSURL.self) {
                group.enter()
                provider.loadObject(ofClass: NSURL.self) { obj, _ in
                    defer { group.leave() }
                    addURL((obj as? NSURL) as URL?)
                }
                continue
            }
            for uti in movieUTIs where provider.hasItemConformingToTypeIdentifier(uti) {
                group.enter()
                provider.loadItem(forTypeIdentifier: uti, options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL {
                        addURL(url)
                    } else if let nsURL = item as? NSURL {
                        addURL(nsURL as URL)
                    } else if let string = item as? String {
                        if let url = URL(string: string), url.isFileURL {
                            addURL(url)
                        } else {
                            addURL(URL(fileURLWithPath: string))
                        }
                    }
                }
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            let fm = FileManager.default
            var topLevelMovieFiles = Set<URL>()
            var rejected: [String] = []
            var sawSubfolders: [String] = []
            var allWarnings: [String] = []

            for url in rawURLs {
                var isDir: ObjCBool = false
                let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
                guard exists else { continue }

                if isDir.boolValue {
                    let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
                    if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                        for child in contents {
                            if let rv = try? child.resourceValues(forKeys: Set(keys)) {
                                if rv.isDirectory == true {
                                    sawSubfolders.append(child.lastPathComponent)
                                } else if rv.isRegularFile == true {
                                    if isAllowedQuickTime(child) {
                                        topLevelMovieFiles.insert(child.standardizedFileURL)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    if isAllowedQuickTime(url) {
                        topLevelMovieFiles.insert(url.standardizedFileURL)
                    } else {
                        rejected.append(url.lastPathComponent)
                    }
                }
            }

            DispatchQueue.main.async {
                if !rejected.isEmpty {
                    let fileList = rejected.count > 5 ?
                        Array(rejected.prefix(5)).joined(separator: ", ") + ", and \(rejected.count - 5) more" :
                        rejected.joined(separator: ", ")
                    allWarnings.append("Non-QuickTime files skipped: \(fileList)")
                }

                if !sawSubfolders.isEmpty {
                    let folderList = sawSubfolders.count > 5 ?
                        Array(sawSubfolders.prefix(5)).joined(separator: ", ") + ", and \(sawSubfolders.count - 5) more" :
                        sawSubfolders.joined(separator: ", ")
                    allWarnings.append("Subfolders not scanned: \(folderList)")
                }

                let existing = Set(AppState.shared?.files.map { $0.url.standardizedFileURL } ?? [])
                let candidates = Array(topLevelMovieFiles.subtracting(existing))
                let wasFolder = rawURLs.contains { url in
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    return isDir.boolValue
                }

                if candidates.isEmpty && wasFolder {
                    if topLevelMovieFiles.isEmpty {
                        allWarnings.append("No QuickTime (.mov) files found in the dropped folder(s)")
                    } else {
                        allWarnings.append("All QuickTime files are already in the queue")
                    }
                }

                if !allWarnings.isEmpty {
                    AppCore.shared.folderAlertTitle = "Drop Processing"
                    AppCore.shared.folderAlertMessage = allWarnings.joined(separator: "\n\n")
                    AppCore.shared.showFolderAlert = true
                }

                guard !candidates.isEmpty else { return }

                if candidates.count > 25 {
                    AppCore.shared.pendingAddAfterConfirm = candidates
                    AppCore.shared.showAmountConfirm = true
                } else {
                    AppState.shared?.addFiles(candidates)

                    // ✅ NEW: kick off Auto-Encode after small batch add
                    if state.settings.autoEncodeOnDrop {
                        state.submit()
                    }

                    for url in candidates {
                        sanityCheckEvenize(for: url, settings: state.settings)

                        // NEW: Deadline-only safety — Block only if SOURCE is not visible to the farm
                        if state.settings.runMode == .remoteDeadline {
                            if case .failure(let error) = EncodeRemote.isInputPathAcceptableForFarm(url) {
                                if let file = AppCore.shared.file(matchingURL: url) {
                                    AppCore.shared.updateFile(id: file.id) { file in
                                        file.status = .blocked
                                        file.statusReason = error.message
                                        file.isChecked = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return accepted
    }

    private func isAllowedQuickTime(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "mov" || ext == "qt"
    }

    private func sanityCheckEvenize(for url: URL, settings: Settings) {
        let asset = AVAsset(url: url)
        guard let v = asset.tracks(withMediaType: .video).first else { return }
        let natural = v.naturalSize
        let tx = v.preferredTransform
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
}


// MARK: - Helpers

private extension View {
    @ViewBuilder
    func ifLet<T, V: View>(_ value: T?, transform: (Self, T) -> V) -> some View {
        if let v = value {
            transform(self, v)
        } else {
            self
        }
    }
}

private struct QueueHeader: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack {
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
            .buttonStyle(.bordered)
        }
    }
}

private struct QueueList: View {
    @EnvironmentObject var state: AppState
    @State private var expandedRowIDs: Set<UUID> = []

    private func suggestedURL(for item: MediaItem) -> URL {
        item.finalOutputURL ?? OutputNamer.suggestedOutputURL(for: item.url, settings: state.settings)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(state.files, id: \.id) { item in
                    UI_QueueRow(
                        item: item,
                        suggested: suggestedURL(for: item),
                        isExpandedExternal: expandedRowIDs.contains(item.id),
                        onToggleExpand: {
                            if expandedRowIDs.contains(item.id) {
                                expandedRowIDs.remove(item.id)
                            } else {
                                expandedRowIDs.insert(item.id)
                            }
                        },
                        isQueuedExternal: item.isChecked,
                        onToggleQueued: { newVal in
                            guard item.status != .encoding else { return }
                            if let idx = AppCore.shared.index(of: item.id) {
                                AppCore.shared.updateFile(at: idx) { file in
                                    file.isChecked = newVal
                                }

                                if newVal,
                                   state.settings.autoEncodeOnDrop,
                                   let refreshed = AppCore.shared.file(at: idx),
                                   refreshed.status == .queued {
                                    state.submit(items: [refreshed])
                                }
                            }
                        },
                        onDelete: {
                            AppCore.shared.removeItem(item.id)
                            expandedRowIDs.remove(item.id)
                        }
                    )
                    .environmentObject(state)
                    .padding(.horizontal, StyleConstants.panelPadding)
                    .padding(.vertical, StyleConstants.listRowVerticalPadding)

                    if item.id != state.files.last?.id {
                        Divider()
                            .padding(.horizontal, StyleConstants.panelPadding)
                    }
                }
            }
            .padding(.vertical, StyleConstants.panelSpacing)
        }
        .onChange(of: state.settings.runMode) { newMode in
            if newMode == .remoteDeadline {
                // Validate sources for farm access; block and uncheck if not visible
                let files = AppCore.shared.filesSnapshot().map { ($0.id, $0.url) }
                for (id, srcURL) in files {
                    if case .failure(let error) = EncodeRemote.isInputPathAcceptableForFarm(srcURL) {
                        AppCore.shared.updateFile(id: id) { file in
                            file.status = .blocked
                            file.statusReason = error.message
                            file.isChecked = false
                        }
                    }
                }
            } else if newMode == .localFFmpeg {
                // Switching back to Local: unblock and re-enable encode
                let ids = AppCore.shared.filesSnapshot().map { $0.id }
                for id in ids {
                    if AppCore.shared.file(id: id)?.status == .blocked {
                        AppCore.shared.updateFile(id: id) { file in
                            file.status = .queued
                            file.statusReason = nil
                            file.isChecked = true
                        }
                    }
                }
            }
        }

        .scrollIndicators(.never)
        .background(Color.clear)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// UI_Queue.swift — tweak EmptyQueueView so it doesn't force top alignment

private struct EmptyQueueView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 28))
                .opacity(0.6)

            Text("Drop QuickTime files or Folder here")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity) // (removed alignment: .top)
    }
}
