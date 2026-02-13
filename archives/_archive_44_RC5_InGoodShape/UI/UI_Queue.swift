//
// MARK: - UI_Queue.swift (Fixed - Remove Height Conflicts, Keep All Functionality)
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct UI_Queue: View {
    @EnvironmentObject var state: AppState
    @StateObject private var queueViewModel = QueueViewModel()
    
    let fixedHeight: CGFloat?
    let isAutoMode: Bool
    let showInternalHandle: Bool
    
    // REMOVED: Internal height management - let parent control height
    @State private var isTargeted = false
    
    private enum C {
        static let corner: CGFloat = 8
        static let minH: CGFloat = 140
        static let maxH: CGFloat = 700
        static let pad: CGFloat = 12
        static let padding: CGFloat = 8
    }
    
    // Default initializer for backward compatibility
    init(fixedHeight: CGFloat? = nil, isAutoMode: Bool = false) {
        self.fixedHeight = fixedHeight
        self.isAutoMode = isAutoMode
        self.showInternalHandle = true
    }
    
    // New initializer with showInternalHandle parameter
    init(fixedHeight: CGFloat? = nil, isAutoMode: Bool = false, showInternalHandle: Bool) {
        self.fixedHeight = fixedHeight
        self.isAutoMode = isAutoMode
        self.showInternalHandle = showInternalHandle
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: C.padding) {
            if !isAutoMode {
                QueueHeader()
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: C.corner)
                    .fill(AppColors.controlBackgroundColor)

                RoundedRectangle(cornerRadius: C.corner)
                    .strokeBorder(
                        isTargeted ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.25),
                        lineWidth: isTargeted ? 2 : 1
                    )
                    .animation(.easeInOut(duration: 0.2), value: isTargeted) // Keep the blue hover effect

                // Content area (unchanged)
                ZStack {
                    if state.files.isEmpty {
                        EmptyQueueView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        QueueList()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(C.pad)
            }
            .clipShape(RoundedRectangle(cornerRadius: C.corner))
            
            // Drop handling (unchanged)
            .onDrop(of: [UTType.fileURL, UTType.movie, UTType.quickTimeMovie],
                    isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
        }

        // KEEP ALL ALERTS - These are essential for file drop functionality
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
    
    // KEEP ALL DROP HANDLING - Essential functionality (unchanged)
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
                    
                    for url in candidates {
                        sanityCheckEvenize(for: url, settings: state.settings)
                    }
                }
            }
        }

        return accepted
    }
    
    // KEEP ALL HELPER FUNCTIONS - Essential functionality
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

// MARK: - Subviews (unchanged - keep all existing functionality)

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
        // CHANGED: Use ScrollView instead of List for external scroll bar control
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
                            if let idx = AppCore.shared.files.firstIndex(where: { $0.id == item.id }) {
                                AppCore.shared.files[idx].isChecked = newVal
                            }
                        },
                        onDelete: {
                            AppCore.shared.removeItem(item.id)
                            expandedRowIDs.remove(item.id)
                        }
                    )
                    .environmentObject(state)
                    .padding(.horizontal, 12) // Manual padding since we're not using List
                    .padding(.vertical, 2)    // Tighter vertical spacing
                    
                    // Divider between rows (since List handled this automatically)
                    if item.id != state.files.last?.id {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.vertical, 8) // Top/bottom padding for the scroll content
        }
        .scrollIndicators(.never) // Hide internal scroll - will appear in external margin
        .background(Color.clear)
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
    }
}
