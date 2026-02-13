//
// MARK: - UI_Queue.swift (Updated)
//

import SwiftUI
import UniformTypeIdentifiers

struct UI_Queue: View {
    @EnvironmentObject var state: AppState
    @StateObject private var queueViewModel = QueueViewModel()
    
    let fixedHeight: CGFloat?
    let isAutoMode: Bool
    
    // Add state for resize functionality
    @State private var height: CGFloat = 240  // Default height
    @State private var isTargeted = false
    
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
                    .stroke(isTargeted ? Color.accentColor.opacity(0.45)
                                       : Color.secondary.opacity(0.25), lineWidth: 1)
                
                ZStack {
                    if state.files.isEmpty {
                        EmptyQueueView()
                    } else {
                        QueueList()
                    }
                }
                .padding(C.pad)
                
                // Show resize handle when not in auto mode
                if !isAutoMode {
                    UI_ResizeHandle(height: $height, minHeight: C.minH, maxHeight: C.maxH)
                        .padding(.bottom, 6)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: C.corner))
            .frame(
                minHeight: C.minH,
                idealHeight: isAutoMode ? nil : height,
                maxHeight: isAutoMode ? .infinity : height
            )
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
        }    }
}

// Add this function inside the UI_Queue struct
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

    group.notify(queue: .global(qos: .userInitiated)) {
        let fm = FileManager.default
        var topLevelMovieFiles = Set<URL>()
        var rejected: [String] = []
        var sawSubfolders: [String] = []

        for url in rawURLs {
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            guard exists else { continue }

            if isDir.boolValue {
                // Folder: scan one level deep only
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
                // Direct file: validate .mov
                if url.pathExtension.lowercased() == "mov" {
                    topLevelMovieFiles.insert(url.standardizedFileURL)
                } else {
                    rejected.append(url.lastPathComponent)
                }
            }
        }

        // Back to main thread for UI updates
        DispatchQueue.main.async {
            var alertParts: [String] = []
            var alertTitle = "Folder Processing"
            
            // Check for invalid files
            if !rejected.isEmpty {
                let fileList = rejected.count > 5 ?
                    Array(rejected.prefix(5)).joined(separator: ", ") + ", and \(rejected.count - 5) more" :
                    rejected.joined(separator: ", ")
                alertParts.append("Non-QuickTime files skipped: \(fileList)")
            }
            
            // Check for subfolders
            if !sawSubfolders.isEmpty {
                let folderList = sawSubfolders.count > 5 ?
                    Array(sawSubfolders.prefix(5)).joined(separator: ", ") + ", and \(sawSubfolders.count - 5) more" :
                    sawSubfolders.joined(separator: ", ")
                alertParts.append("Subfolders not scanned: \(folderList)")
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
                    alertParts.append("No QuickTime (.mov) files found in the dropped folder(s)")
                } else {
                    alertParts.append("All QuickTime files are already in the queue")
                }
            }
            
            // Show consolidated alert if there are any issues to report
            if !alertParts.isEmpty {
                AppCore.shared.folderAlertTitle = alertTitle
                AppCore.shared.folderAlertMessage = alertParts.joined(separator: "\n\n")
                AppCore.shared.showFolderAlert = true
            }
            
            // Continue with file processing if we have candidates
            guard !candidates.isEmpty else { return }
            
            // 25+ confirmation (separate from issues alert)
            if candidates.count > 25 {
                AppCore.shared.pendingAddAfterConfirm = candidates
                AppCore.shared.showAmountConfirm = true
            } else {
                AppState.shared?.addFiles(candidates)
            }
        }
    }

    return accepted
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

private struct QueueList: View {
    @EnvironmentObject var state: AppState
    @StateObject private var queueViewModel = QueueViewModel()
    
    var body: some View {
        if state.files.isEmpty {
            EmptyQueueView()
        } else {
            ScrollViewReader { proxy in
                List(state.files, id: \.id, selection: $state.selectedIDs) { item in
                    QueueRow(item: item)
                        .environmentObject(queueViewModel)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
                .listStyle(.plain)
                .contextMenu {
                    QueueContextMenu()
                        .environmentObject(state)
                }
            }
        }
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
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
        )
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }
    
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

        group.notify(queue: .global(qos: .userInitiated)) {
            let fm = FileManager.default
            var topLevelMovieFiles = Set<URL>()
            var rejected: [String] = []
            var sawSubfolders: [String] = []

            for url in rawURLs {
                var isDir: ObjCBool = false
                let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
                guard exists else { continue }

                if isDir.boolValue {
                    // Folder: scan one level deep only
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
                    // Direct file: validate .mov
                    if url.pathExtension.lowercased() == "mov" {
                        topLevelMovieFiles.insert(url.standardizedFileURL)
                    } else {
                        rejected.append(url.lastPathComponent)
                    }
                }
            }

            // Back to main thread for UI updates
            // Back to main thread for UI updates
            DispatchQueue.main.async {
                var alertParts: [String] = []
                var alertTitle = "Folder Processing"
                
                // Check for invalid files
                if !rejected.isEmpty {
                    let fileList = rejected.count > 5 ?
                        Array(rejected.prefix(5)).joined(separator: ", ") + ", and \(rejected.count - 5) more" :
                        rejected.joined(separator: ", ")
                    alertParts.append("Non-QuickTime files skipped: \(fileList)")
                }
                
                // Check for subfolders
                if !sawSubfolders.isEmpty {
                    let folderList = sawSubfolders.count > 5 ?
                        Array(sawSubfolders.prefix(5)).joined(separator: ", ") + ", and \(sawSubfolders.count - 5) more" :
                        sawSubfolders.joined(separator: ", ")
                    alertParts.append("Subfolders not scanned: \(folderList)")
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
                        alertParts.append("No QuickTime (.mov) files found in the dropped folder(s)")
                    } else {
                        alertParts.append("All QuickTime files are already in the queue")
                    }
                }
                
                // Show consolidated alert if there are any issues to report
                if !alertParts.isEmpty {
                    AppCore.shared.folderAlertTitle = alertTitle
                    AppCore.shared.folderAlertMessage = alertParts.joined(separator: "\n\n")
                    AppCore.shared.showFolderAlert = true
                }
                
                // Continue with file processing if we have candidates
                guard !candidates.isEmpty else { return }
                
                // 25+ confirmation (separate from issues alert)
                if candidates.count > 25 {
                    AppCore.shared.pendingAddAfterConfirm = candidates
                    AppCore.shared.showAmountConfirm = true
                } else {
                    AppState.shared?.addFiles(candidates)
                }
            }
        }

        return accepted
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
