// =============================
// File: UI_Queue.swift  (NSTableView wrapper; variable row height; expand only down; now supports auto-expand)
// =============================
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct UI_Queue: View {
    @EnvironmentObject var state: AppState

    // Add parameters for expandable behavior
    var fixedHeight: CGFloat? = nil  // If provided, use this height instead of user-resizable
    var isAutoMode: Bool = false     // Whether we're in auto-encode mode

    // 1) Bump constants to better fit content (keeps same top/bottom margin folded/unfolded)
    enum C {
        static let corner: CGFloat        = 8
        static let minH: CGFloat          = 140
        static let maxH: CGFloat          = 700
        static let initH: CGFloat         = 240
        static let pad: CGFloat           = 12
        static let rowH_collapsed: CGFloat = 72 // was 64   // earlier was 56
        static let rowH_expanded:  CGFloat = 132 // was 108  // earlier was 128
    }

    @State private var isTargeted = false
    @State private var height: CGFloat = C.initH

    @State private var showInvalidAlert = false
    @State private var invalidNames: [String] = []
    
    @State private var showTraverseAlert = false
    @State private var skippedSubfolderNames: [String] = []

    @State private var pendingAddAfterConfirm: [URL] = []
    @State private var showAmountConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: isAutoMode ? 0 : 8) {
            // Auto-Encode, everything goes but the Queue
            if !isAutoMode {
                HStack {
                    UI_SectionHeader("Files Queued")
                    Spacer()

                    // Fixed-size container that never changes dimensions
                    VStack(alignment: .trailing, spacing: 2) {
                        // Top line: spinner + text (always same height)
                        HStack(spacing: 6) {
                            Group {
                                if state.isBackgroundProcessing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .controlSize(.small)
                                } else {
                                    Circle()  // Same size as spinner but invisible
                                        .frame(width: 16, height: 16)
                                        .opacity(0)
                                }
                            }

                            Text(state.isBackgroundProcessing
                                    ? "Processing metadata... (\(state.backgroundProcessingCount) remaining)"
                                    : " ")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(minHeight: 16)
                        }
                        .frame(height: 20)

                        // NEW middle line: pre-encode total estimate (shows only when nothing is encoding)
                        Group {
                            let snap = state.estimateTotalEncodeSeconds()
                            if snap.count > 0 && !state.files.contains(where: { $0.status == .encoding }) {
                                Text("Est. total time: \(state.formatHMS(snap.seconds)) for \(snap.count) item\(snap.count == 1 ? "" : "s")")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                // keep the same vertical rhythm when hidden
                                Text(" ").font(.caption2).opacity(0)
                            }
                        }

                        // Bottom line: progress bar (visible only during background work)
                        ProgressView(value: state.backgroundProgress)
                            .frame(width: 120, height: 6)
                            .opacity(state.isBackgroundProcessing ? 1.0 : 0.0)
                    }
                    .frame(width: 200, height: 40) // was 28 — give room for the extra caption line
                    .padding(.trailing, 8)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }


            ZStack {
                RoundedRectangle(cornerRadius: C.corner)
                    .fill(Color(NSColor.windowBackgroundColor))
                RoundedRectangle(cornerRadius: C.corner)
                    .stroke(isTargeted ? Color.accentColor.opacity(0.45)
                                       : Color.secondary.opacity(0.25), lineWidth: 1)

                ZStack {
                    if state.files.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.on.square")
                                .font(.system(size: 28))
                                .opacity(0.6)
                            Text("Drop QuickTime files here")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    QueueTableView(
                        files: $state.files,
                        selectedIDs: $state.selectedIDs,
                        settings: state.settings,
                        stateRef: state
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(C.pad)

                // Only show resize handle when not in auto mode
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
                handleExternalDrop(providers: providers)
            }
        }
        .animation(.easeInOut(duration: 0.20), value: isAutoMode)
        
        // Only Quicktimes need apply
        .alert("Only QuickTime .mov files are supported", isPresented: $showInvalidAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(invalidNames.joined(separator: ", "))
        }
        
        // Subfolder warning (no subdirs get scanned)
        .alert("Subfolders not scanned", isPresented: $showTraverseAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            let names = skippedSubfolderNames.prefix(12)
            Text( (names.isEmpty ? "This folder contains subfolders which were not scanned." :
                  "These subfolders were not scanned:\n" + names.joined(separator: ", ")) )
        }

        // Amount confirmation (>25 files triggers warning)
        .alert("Add \(pendingAddAfterConfirm.count) files to the queue?", isPresented: $showAmountConfirm) {
            Button("Cancel", role: .cancel) {
                pendingAddAfterConfirm = []
            }
            Button("Add All", role: .destructive) {
                finalizeAdd(pendingAddAfterConfirm)
                pendingAddAfterConfirm = []
            }
        } message: {
            Text("Large add detected. For safety, folders are not scanned recursively.\nYou can adjust later from the queue.")
        }

    }

    // MARK: - External file/folder drop (first-level only + protections)
    private func handleExternalDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        var rawURLs = Set<URL>()         // direct files/folders from the drop
        var rejected: [String] = []      // non-QuickTime files dropped directly (not via folder scan)
        let group = DispatchGroup()

        func push(_ maybe: URL?) {
            guard let u = maybe, u.isFileURL else { return }
            rawURLs.insert(u.standardizedFileURL)
        }

        // Accept fileURL flavor (covers files and folders)
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            group.enter()
            p.loadObject(ofClass: NSURL.self) { obj, _ in
                defer { group.leave() }
                push((obj as? NSURL) as URL?)
            }
        }

        // Accept movie / quicktime flavors (files only)
        let movieUTIs = [UTType.movie.identifier, UTType.quickTimeMovie.identifier]
        for p in providers where movieUTIs.contains(where: { p.hasItemConformingToTypeIdentifier($0) }) {
            accepted = true
            if p.canLoadObject(ofClass: NSURL.self) {
                group.enter()
                p.loadObject(ofClass: NSURL.self) { obj, _ in
                    defer { group.leave() }
                    push((obj as? NSURL) as URL?)
                }
                continue
            }
            for uti in movieUTIs where p.hasItemConformingToTypeIdentifier(uti) {
                group.enter()
                p.loadItem(forTypeIdentifier: uti, options: nil) { item, _ in
                    defer { group.leave() }
                    if let u = item as? URL { push(u) }
                    else if let ns = item as? NSURL { push(ns as URL) }
                    else if let s = item as? String {
                        if let u = URL(string: s), u.isFileURL { push(u) }
                        else { push(URL(fileURLWithPath: s)) }
                    }
                }
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            // Split dropped URLs into files vs folders
            let fm = FileManager.default
            var topLevelMovieFiles = Set<URL>()
            var sawSubfolders: [String] = []

            for url in rawURLs {
                var isDir: ObjCBool = false
                let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
                guard exists else { continue }

                if isDir.boolValue {
                    // First-level scan ONLY (no recursion)
                    let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isPackageKey, .contentTypeKey]
                    if let kids = try? fm.contentsOfDirectory(at: url,
                                                              includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                        for child in kids {
                            if let rv = try? child.resourceValues(forKeys: Set(keys)) {
                                if rv.isDirectory == true {
                                    // record subfolder name (not scanning it)
                                    sawSubfolders.append(child.lastPathComponent)
                                } else if rv.isRegularFile == true {
                                    if UI_IsAllowedQuickTime(child) {
                                        topLevelMovieFiles.insert(child.standardizedFileURL)
                                    } else {
                                        // silently ignore non-mov inside folder (keeps alert tidy)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Direct file drop: keep QuickTime only; reject others
                    if UI_IsAllowedQuickTime(url) {
                        topLevelMovieFiles.insert(url.standardizedFileURL)
                    } else {
                        rejected.append(url.lastPathComponent)
                    }
                }
            }

            // Back to main for UI updates / confirmations
            DispatchQueue.main.async {
                // Warn about non-QuickTime direct items (existing behavior)
                if !rejected.isEmpty {
                    invalidNames = rejected.count > 12 ? Array(rejected.prefix(12)) + ["…"] : rejected
                    showInvalidAlert = true
                }

                // Warn that subfolders were NOT scanned
                if !sawSubfolders.isEmpty {
                    skippedSubfolderNames = sawSubfolders
                    showTraverseAlert = true
                }

                // Deduplicate against queue and apply amount protection
                let existing = Set(state.files.map { $0.url.standardizedFileURL })
                let candidates = Array(topLevelMovieFiles.subtracting(existing))

                guard !candidates.isEmpty else { return }

                // Amount warning if > 25
                if candidates.count > 25 {
                    pendingAddAfterConfirm = candidates
                    showAmountConfirm = true
                } else {
                    finalizeAdd(candidates)
                }
            }
        }

        return accepted
    }

    // Finalize add + optional auto-encode (shared by normal and confirmed path)
    private func finalizeAdd(_ newOnes: [URL]) {
        state.addFiles(newOnes)
        if state.settings.autoEncodeOnDrop {
            state.submit()
        }
    }

}

// MARK: - Native NSTableView wrapper (variable row height; single row expands)
private struct QueueTableView: NSViewRepresentable {
    @Binding var files: [MediaItem]
    @Binding var selectedIDs: Set<MediaItem.ID>
    var settings: Settings
    weak var stateRef: AppState?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let table = NSTableView()
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.headerView = nil
        table.rowHeight = UI_Queue.C.rowH_collapsed
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true

        // Drag & drop for reordering
        table.registerForDraggedTypes([.rowDragType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)

        // Columns: checkbox + main content
        let checkCol = NSTableColumn(identifier: .checkCol)
        checkCol.width = 28; checkCol.minWidth = 28; checkCol.maxWidth = 32
        table.addTableColumn(checkCol)

        let mainCol = NSTableColumn(identifier: .mainCol)
        mainCol.resizingMask = .autoresizingMask
        table.addTableColumn(mainCol)

        table.delegate = context.coordinator
        table.dataSource = context.coordinator

        scroll.documentView = table
        context.coordinator.table = table
        context.coordinator.reloadAll()

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncSelectionToTable()
        context.coordinator.reloadVisibleIfNeeded()
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: QueueTableView
        weak var table: NSTableView?

        /// Which rows are expanded (by MediaItem.id)
        private var expandedIDs: Set<UUID> = []

        init(_ parent: QueueTableView) { self.parent = parent }

        // MARK: DataSource
        func numberOfRows(in tableView: NSTableView) -> Int { parent.files.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0 && row < parent.files.count else { return nil }
            let item = parent.files[row]

            if tableColumn?.identifier == .checkCol {
                let id = "CheckCell"
                let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(id), owner: self) as? NSTableCellView
                    ?? {
                        let c = NSTableCellView()
                        c.identifier = NSUserInterfaceItemIdentifier(id)
                        let btn = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleCheckbox(_:)))
                        btn.setButtonType(.switch)
                        btn.bezelStyle = .regularSquare
                        btn.translatesAutoresizingMaskIntoConstraints = false
                        c.addSubview(btn)
                        NSLayoutConstraint.activate([
                            btn.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                            btn.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4)
                        ])
                        return c
                    }()

                if let btn = cell.subviews.compactMap({ $0 as? NSButton }).first {
                    btn.tag = row
                    btn.state = item.isChecked ? .on : .off
                    btn.isEnabled = !(item.status == .blocked || item.status == .encoding)
                    btn.toolTip = item.status == .blocked
                        ? (item.statusReason ?? "Blocked")
                        : "Check to include in Encode"
                }
                return cell
            }

            // Main SwiftUI row
            let id = "MainCell"
            let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(id), owner: self) as? NSTableCellView
                ?? {
                    let c = NSTableCellView()
                    c.identifier = NSUserInterfaceItemIdentifier(id)
                    let host = NSHostingView(rootView: AnyView(EmptyView()))
                    host.translatesAutoresizingMaskIntoConstraints = false
                    host.sizingOptions = [.intrinsicContentSize]
                    c.addSubview(host)
                    NSLayoutConstraint.activate([
                        host.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 0),
                        host.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                        host.topAnchor.constraint(equalTo: c.topAnchor),
                        host.bottomAnchor.constraint(equalTo: c.bottomAnchor)
                    ])
                    return c
                }()

            let isExpanded = expandedIDs.contains(item.id)
            let rowView = UI_QueueRow(
                item: item,
                suggested: OutputNamer.suggestedOutputURL(for: item.url, settings: parent.settings),
                isExpandedExternal: isExpanded,
                onToggleExpand: { [weak self] in self?.toggleExpanded(for: item.id) }
            )
            .environmentObject(parent.stateRef ?? AppState.shared ?? AppState())

            if let host = cell.subviews.compactMap({ $0 as? NSHostingView<AnyView> }).first {
                host.rootView = AnyView(rowView)
            } else if let host = cell.subviews.first(where: { $0 is NSHostingView<EmptyView> }) as? NSHostingView<EmptyView> {
                let newHost = NSHostingView(rootView: AnyView(rowView))
                newHost.translatesAutoresizingMaskIntoConstraints = false
                newHost.sizingOptions = [.intrinsicContentSize]
                cell.addSubview(newHost)
                host.removeFromSuperview()
                NSLayoutConstraint.activate([
                    newHost.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 0),
                    newHost.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    newHost.topAnchor.constraint(equalTo: cell.topAnchor),
                    newHost.bottomAnchor.constraint(equalTo: cell.bottomAnchor)
                ])
            } else {
                let host = NSHostingView(rootView: AnyView(rowView))
                host.translatesAutoresizingMaskIntoConstraints = false
                host.sizingOptions = [.intrinsicContentSize]
                cell.addSubview(host)
                NSLayoutConstraint.activate([
                    host.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 0),
                    host.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    host.topAnchor.constraint(equalTo: cell.topAnchor),
                    host.bottomAnchor.constraint(equalTo: cell.bottomAnchor)
                ])
            }

            return cell
        }

        // Variable row height (expand only downward)
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row >= 0 && row < parent.files.count else { return UI_Queue.C.rowH_collapsed }
            let id = parent.files[row].id
            return expandedIDs.contains(id) ? UI_Queue.C.rowH_expanded : UI_Queue.C.rowH_collapsed
        }

        // MARK: Selection bridging
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tv = table else { return }
            let indexes = tv.selectedRowIndexes
            var newSel = Set<UUID>()
            indexes.forEach { idx in
                if idx >= 0 && idx < parent.files.count {
                    newSel.insert(parent.files[idx].id)
                }
            }
            if parent.selectedIDs != newSel {
                parent.selectedIDs = newSel
            }
        }

        func syncSelectionToTable() {
            guard let tv = table else { return }
            var toSelect = IndexSet()
            for (idx, item) in parent.files.enumerated() {
                if parent.selectedIDs.contains(item.id) { toSelect.insert(idx) }
            }
            if tv.selectedRowIndexes != toSelect {
                tv.selectRowIndexes(toSelect, byExtendingSelection: false)
            }
        }

        // MARK: Checkbox
        @objc private func toggleCheckbox(_ sender: NSButton) {
            let row = sender.tag
            guard row >= 0 && row < parent.files.count else { return }
            parent.files[row].isChecked = (sender.state == .on)
        }

        // MARK: Expand/collapse
        private func toggleExpanded(for id: UUID) {
            guard let tv = table,
                  let row = parent.files.firstIndex(where: { $0.id == id }) else { return }

            if expandedIDs.contains(id) { expandedIDs.remove(id) } else { expandedIDs.insert(id) }

            tv.beginUpdates()
            tv.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
            tv.endUpdates()
            tv.scrollRowToVisible(row)

            // Refresh both columns so the chevron updates immediately
            tv.reloadData(forRowIndexes: IndexSet(integer: row),
                          columnIndexes: IndexSet(integersIn: 0..<(tv.numberOfColumns)))
        }

        // MARK: Drag / Drop (internal reordering)
        func tableView(_ tableView: NSTableView,
                       pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            let pbItem = NSPasteboardItem()
            pbItem.setString(String(row), forType: .rowDragType)
            return pbItem
        }

        func tableView(_ tableView: NSTableView,
                       validateDrop info: NSDraggingInfo,
                       proposedRow row: Int,
                       proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            tableView.setDropRow(row, dropOperation: .above) // native blue insertion line
            return .move
        }

        func tableView(_ tableView: NSTableView,
                       acceptDrop info: NSDraggingInfo,
                       row: Int,
                       dropOperation: NSTableView.DropOperation) -> Bool {
            guard let str = info.draggingPasteboard.string(forType: .rowDragType),
                  let fromRow = Int(str),
                  fromRow >= 0, fromRow < parent.files.count else { return false }

            var toRow = row
            if fromRow < toRow { toRow -= 1 } // account for removal shift
            toRow = max(0, min(toRow, parent.files.count - 1))
            if fromRow == toRow { return false }

            let moved = parent.files.remove(at: fromRow)
            parent.files.insert(moved, at: toRow)

            tableView.reloadData()
            syncSelectionToTable()
            return true
        }

        // MARK: Helpers
        func reloadAll() {
            table?.reloadData()
            syncSelectionToTable()
        }

        func reloadVisibleIfNeeded() {
            table?.reloadData()
            syncSelectionToTable()
        }
    }
}

// MARK: - Pasteboard type ids
private extension NSPasteboard.PasteboardType {
    static let rowDragType = NSPasteboard.PasteboardType("com.mrhevc.queue.row")
}

private extension NSUserInterfaceItemIdentifier {
    static let checkCol = NSUserInterfaceItemIdentifier("check")
    static let mainCol  = NSUserInterfaceItemIdentifier("main")
}
