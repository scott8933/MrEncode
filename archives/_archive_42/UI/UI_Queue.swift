//
// MARK: - UI_Queue.swift (Fixed Drop Handling)
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct UI_Queue: View {
    @EnvironmentObject var state: AppState
    @StateObject private var queueViewModel = QueueViewModel()
    
    let fixedHeight: CGFloat?
    let isAutoMode: Bool
    
    // Add state for resize functionality
    @State private var height: CGFloat = 240  // Default height
    @State private var isTargeted = false
    @State private var hovering = false
    @State private var dragStartHeight: CGFloat = 0
    @State private var isDragging = false
    @State private var isResizing = false

    
    private enum C {
        static let corner: CGFloat = 8
        static let minH: CGFloat = 140
        static let maxH: CGFloat = 700
        static let pad: CGFloat = 12
        static let rowHeight: CGFloat = 44
        static let padding: CGFloat = 8
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: C.padding) {
            if !isAutoMode {
                QueueHeader()
            }
            
            // Main queue container with resize capability
            ZStack {
                RoundedRectangle(cornerRadius: C.corner)
                    .fill(Color(NSColor.windowBackgroundColor))

                RoundedRectangle(cornerRadius: C.corner)
                    .stroke(isTargeted ? Color.accentColor.opacity(0.8)
                                       : Color.secondary.opacity(0.25),
                            lineWidth: isTargeted ? 2 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isTargeted)

                ZStack {
                    if state.files.isEmpty {
                        EmptyQueueView()
                            .background(Color.clear)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        QueueList()
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)   // List (macOS 13+) — noop for ScrollView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.clear)
                            .scrollDisabled(isResizing)         // prevent scroll vs resize fight
                    }
                }
                .padding(C.pad)

                // Show resize handle when not in auto mode
                if !isAutoMode {
                    UI_ResizeHandle(
                        height: $height,
                        minHeight: C.minH,
                        maxHeight: C.maxH,
                        style: .light,
                        onResizingChanged: { isResizing = $0 }   // <-- if you added this param
                    )
                    .padding(.bottom, 6)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: C.corner))
            .frame(height: isAutoMode ? nil : height)     // ← single source of truth for height
            .animation(nil, value: height)                // ← no implicit tween on height
            .onAppear {
                if let fh = fixedHeight, !isAutoMode {
                    height = min(max(fh, C.minH), C.maxH) // (optional) honor initial height once
                }
            }

            
            // CONSOLIDATED DROP HANDLING - This handles all drops regardless of queue state
            .onDrop(of: [UTType.fileURL, UTType.movie, UTType.quickTimeMovie],
                    isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
        }

        // Alerts on Drag Drop
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
                AppState.shared?.addFiles(AppCore.shared.pendingAddAfterConfirm)
                AppCore.shared.pendingAddAfterConfirm = []
                AppCore.shared.showAmountConfirm = false
            }
        } message: {
            Text("Large add detected. For safety, folders are not scanned recursively.")
        }
    }
    
    // CONSOLIDATED DROP HANDLER - Single source of truth for all drop handling
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        var rawURLs = Set<URL>()
        let group = DispatchGroup()

        // Helper function to add URLs
        func addURL(_ url: URL?) {
            guard let url = url, url.isFileURL else { return }
            rawURLs.insert(url.standardizedFileURL)
        }

        // Accept fileURL flavor (covers files and folders) - use loadObject like the working version
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            group.enter()
            provider.loadObject(ofClass: NSURL.self) { obj, _ in
                defer { group.leave() }
                addURL((obj as? NSURL) as URL?)
            }
        }

        // Accept movie / quicktime flavors (files only)
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
            var allWarnings: [String] = [] // Collect all warnings to show in one alert

            for url in rawURLs {
                var isDir: ObjCBool = false
                let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
                guard exists else { continue }

                if isDir.boolValue {
                    // Folder: scan one level deep only
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
                                    // Silently ignore non-mov files inside folders to keep alerts tidy
                                }
                            }
                        }
                    }
                } else {
                    // Direct file: validate .mov
                    if isAllowedQuickTime(url) {
                        topLevelMovieFiles.insert(url.standardizedFileURL)
                    } else {
                        rejected.append(url.lastPathComponent)
                    }
                }
            }

            // Back to main thread for UI updates
            DispatchQueue.main.async {
                // Build consolidated warning messages
                
                // Check for invalid direct files
                if !rejected.isEmpty {
                    let fileList = rejected.count > 5 ?
                        Array(rejected.prefix(5)).joined(separator: ", ") + ", and \(rejected.count - 5) more" :
                        rejected.joined(separator: ", ")
                    allWarnings.append("Non-QuickTime files skipped: \(fileList)")
                }
                
                // Check for subfolders
                if !sawSubfolders.isEmpty {
                    let folderList = sawSubfolders.count > 5 ?
                        Array(sawSubfolders.prefix(5)).joined(separator: ", ") + ", and \(sawSubfolders.count - 5) more" :
                        sawSubfolders.joined(separator: ", ")
                    allWarnings.append("Subfolders not scanned: \(folderList)")
                }
                
                // Check if no .mov files found in folder(s)
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
                
                // Show consolidated warning alert if there are any issues to report
                if !allWarnings.isEmpty {
                    AppCore.shared.folderAlertTitle = "Drop Processing"
                    AppCore.shared.folderAlertMessage = allWarnings.joined(separator: "\n\n")
                    AppCore.shared.showFolderAlert = true
                }
                
                // Continue with file processing if we have candidates
                guard !candidates.isEmpty else { return }
                
                // Large batch confirmation (separate from warnings alert)
                if candidates.count > 25 {
                    AppCore.shared.pendingAddAfterConfirm = candidates
                    AppCore.shared.showAmountConfirm = true
                } else {
                    // Add files and run sanity checks
                    AppState.shared?.addFiles(candidates)
                    
                    // Run sanity checks for each accepted file (like DropZoneView did)
                    for url in candidates {
                        sanityCheckEvenize(for: url, settings: state.settings)
                    }
                }
            }
        }

        return accepted
    }
    
    // MARK: - Helper Functions
    
    /// Check if file is allowed QuickTime format
    private func isAllowedQuickTime(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "mov" || ext == "qt"
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
}

// MARK: - Subviews

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

// MARK: - QueueList (revised: chevron + queued checkbox + delete X; no List selection)

private struct QueueList: View {
    @EnvironmentObject var state: AppState
    @State private var expandedRowIDs: Set<UUID> = []

    // Use the same suggestion logic you were using pre-refactor
    private func suggestedURL(for item: MediaItem) -> URL {
        item.finalOutputURL ?? OutputNamer.suggestedOutputURL(for: item.url, settings: state.settings)
    }

    var body: some View {
        // IMPORTANT: no `selection:` binding → no row highlight
        List(state.files, id: \.id) { item in
            UI_QueueRow(
                item: item,
                suggested: suggestedURL(for: item),
                // chevron expand/collapse
                isExpandedExternal: expandedRowIDs.contains(item.id),
                onToggleExpand: {
                    if expandedRowIDs.contains(item.id) {
                        expandedRowIDs.remove(item.id)
                    } else {
                        expandedRowIDs.insert(item.id)
                    }
                },
                // "Queued" checkbox – parent-controlled to avoid List selection coupling
                isQueuedExternal: item.isChecked,
                onToggleQueued: { newVal in
                    // Don't allow changing queued state while actively encoding
                    guard item.status != .encoding else { return }
                    if let idx = AppCore.shared.files.firstIndex(where: { $0.id == item.id }) {
                        AppCore.shared.files[idx].isChecked = newVal
                    }
                },
                // Delete (X)
                onDelete: {
                    AppCore.shared.removeItem(item.id)   // <– use a unique, non-ambiguous helper
                    expandedRowIDs.remove(item.id)
                }
            )
            .environmentObject(state) // UI_QueueRow expects AppState
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 8))
        }
        .listStyle(.plain)
        .background(Color.clear)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 28) // feels tighter; adjust to taste
    }
}

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
        
        // REMOVED: No separate onDrop here - parent container handles all drops
    }
}

private struct QueueRow: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var queueViewModel: QueueViewModel
    let item: MediaItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            CheckboxView(
                isChecked: item.isChecked,
                isEnabled: queueViewModel.canToggleItem(item)
            ) {
                toggleItem()
            }
            
            // Status Icon
            Image(systemName: queueViewModel.statusIcon(for: item.status))
                .foregroundColor(queueViewModel.statusColor(for: item.status))
                .frame(width: 16)
            
            // File Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.url.lastPathComponent)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if queueViewModel.canRemoveItem(item) {
                        Button(action: { removeItem() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from queue")
                    }
                }
                
                Text(queueViewModel.sourceDisplayText(for: item))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(queueViewModel.destinationDisplayText(for: item, settings: state.settings))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Progress bar if encoding
                let progressInfo = queueViewModel.progressInfo(for: item)
                if progressInfo.showProgress {
                    VStack(spacing: 2) {
                        if progressInfo.progress > 0 {
                            ProgressView(value: progressInfo.progress)
                        } else {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        
                        if let text = progressInfo.text {
                            Text(text)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .help(queueViewModel.statusTooltip(for: item))
        .contextMenu {
            ItemContextMenu(item: item)
                .environmentObject(state)
        }
    }
    
    private func toggleItem() {
        guard queueViewModel.canToggleItem(item) else { return }
        
        if let index = state.files.firstIndex(where: { $0.id == item.id }) {
            // Direct mutation via AppCore since we need to modify the files array
            AppCore.shared.files[index].isChecked.toggle()
        }
    }
    
    private func removeItem() {
        guard queueViewModel.canRemoveItem(item) else { return }
        
        state.removeItems(withIDs: [item.id])
        state.selectedIDs.remove(item.id)
    }
}

private struct CheckboxView: View {
    let isChecked: Bool
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .foregroundColor(isEnabled ? (isChecked ? .accentColor : .primary) : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct QueueContextMenu: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        if !state.selectedIDs.isEmpty {
            Button("Remove Selected") {
                state.removeItems(withIDs: state.selectedIDs)
                state.selectedIDs.removeAll()
            }
            .disabled(state.selectedIDs.isEmpty)
            
            Divider()
            
            Button("Check Selected") {
                for id in state.selectedIDs {
                    if let index = state.files.firstIndex(where: { $0.id == id }),
                       state.files[index].status != .encoding {
                        AppCore.shared.files[index].isChecked = true
                    }
                }
            }
            
            Button("Uncheck Selected") {
                for id in state.selectedIDs {
                    if let index = state.files.firstIndex(where: { $0.id == id }),
                       state.files[index].status != .encoding {
                        AppCore.shared.files[index].isChecked = false
                    }
                }
            }
        } else {
            Button("Select All") {
                state.selectedIDs = Set(state.files.map { $0.id })
            }
            
            Button("Check All") {
                for index in state.files.indices {
                    if state.files[index].status != .encoding {
                        AppCore.shared.files[index].isChecked = true
                    }
                }
            }
            
            Button("Uncheck All") {
                for index in state.files.indices {
                    if state.files[index].status != .encoding {
                        AppCore.shared.files[index].isChecked = false
                    }
                }
            }
        }
        
        Divider()
        
        Button("Clear All") {
            state.clearAllNonEncoding()
            state.selectedIDs.removeAll()
        }
        .disabled(state.files.filter { $0.status != .encoding }.isEmpty)
    }
}

private struct ItemContextMenu: View {
    @EnvironmentObject var state: AppState
    let item: MediaItem
    
    var body: some View {
        Button(item.isChecked ? "Uncheck" : "Check") {
            if let index = state.files.firstIndex(where: { $0.id == item.id }),
               state.files[index].status != .encoding {
                AppCore.shared.files[index].isChecked.toggle()
            }
        }
        .disabled(item.status == .encoding)
        
        if let outputURL = item.finalOutputURL {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: "")
            }
        }
        
        if let logURL = item.logURL, FileManager.default.fileExists(atPath: logURL.path) {
            Button("Show Log") {
                NSWorkspace.shared.open(logURL)
            }
        }
        
        Divider()
        
        Button("Remove") {
            state.removeItems(withIDs: [item.id])
            state.selectedIDs.remove(item.id)
        }
        .disabled(item.status == .encoding)
    }
}
