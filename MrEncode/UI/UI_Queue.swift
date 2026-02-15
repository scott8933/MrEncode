//
//  UI_Queue.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/16/25.
//

// MARK: - UI_Queue.swift (Revised to source sizes/colors from AppColors and follow parent height)

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
#if os(macOS)
import AppKit
#endif

struct UI_Queue: View {
    @EnvironmentObject var state: AppState
    
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    @StateObject private var queueViewModel = QueueViewModel()
#if os(macOS)
    @State private var isShowingImportPanel = false
#endif

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
        ZStack(alignment: .top) {
            // Panel fill
            RoundedRectangle(cornerRadius: StyleConstants.Spacing.panelCornerRadius)
                .fill(C.bgDropZone)
            
            // Panel stroke
            RoundedRectangle(cornerRadius: StyleConstants.Spacing.panelCornerRadius)
                .strokeBorder(
                    isTargeted
                        ? Color.accentColor.opacity(StyleConstants.Borders.strokeOpacityActive)
                        : C.strokeSubtle,
                    lineWidth: isTargeted ? StyleConstants.Borders.activeBorderLineWidth : StyleConstants.Borders.borderLineWidth
                )
                .animation(.easeInOut(duration: StyleConstants.Motion.hoverAnimationDuration), value: isTargeted)

            // Content
            if state.files.isEmpty {
                ZStack {
                    // DropZone background
                    RoundedRectangle(cornerRadius: StyleConstants.Spacing.panelCornerRadius)
                        .fill(C.bgDropZone)
                        .overlay(
                            RoundedRectangle(cornerRadius: StyleConstants.Spacing.panelCornerRadius)
                                .stroke(C.strokeDropZone, lineWidth: 1)
                        )

                    VStack {
                        Spacer()
                        EmptyQueueView()
                        Spacer()
                    }
                    .padding(StyleConstants.Spacing.panelPaddingV_expanded)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ZStack(alignment: .top) {
                    QueueList()
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(StyleConstants.Spacing.panelPaddingV_expanded)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .ifLet(fixedHeight) { view, h in
            view.frame(height: h, alignment: .top) // parent-controlled Queue height
        }
        
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDroppedProviders(providers)
            return true
        }

        #if os(macOS)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        openAddPanel()
                    }
                )
        #endif
        
                .contextMenu {
                    Button("Import Media…") {
                        NotificationCenter.default.post(name: .mrEncodeImportMediaRequested, object: nil)
                    }

                    Divider()

                    Button("Save Queue…") {
                        NotificationCenter.default.post(name: .mrEncodeSaveQueueRequested, object: nil)
                    }
                    .disabled(state.files.isEmpty)

                    Button("Open Queue…") {
                        NotificationCenter.default.post(name: .mrEncodeOpenQueueRequested, object: nil)
                    }

                    Button("Append Queue…") {
                        NotificationCenter.default.post(name: .mrEncodeAppendQueueRequested, object: nil)
                    }
                }


        
        // Button overlays
        .overlay(alignment: .bottom) {
            HStack(spacing: 24) {

                // Leftmost: AutoEncode
                AutoEncodeFloatingButton()
                    .environmentObject(state)

                Spacer(minLength: 20)

                // Triplet (Encode/Pause/Cancel) hugging Trash on the left
                EncodePauseCancelFloatingGroup()
                    .environmentObject(state)

                // Trash (rightmost)
                TrashFloatingButton()
                    .environmentObject(state)
            }
            .padding(.horizontal, StyleConstants.Spacing.panelPaddingV_expanded)
            .padding(.bottom, StyleConstants.Spacing.panelPaddingV_expanded)
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
                AppState.shared?.confirmPendingImportMedia()
            }

        } message: {
            Text("Large add detected. For safety, folders are not scanned recursively.")
        }
    }
    
    func handleDroppedProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSURL.self) {
                provider.loadObject(ofClass: NSURL.self) { obj, _ in
                    guard let nsurl = obj as? NSURL, let url = nsurl as URL? else { return }
                    DispatchQueue.main.async {
                        state.importMedia(from: [url], alertTitle: "Add Processing")
                    }
                }
            }
        }
    }


    
#if os(macOS)
    private func openAddPanel() {
        
        guard !isShowingImportPanel else { return }
            isShowingImportPanel = true

            let panel = NSOpenPanel()
        
        panel.title = "Add Files to Queue"
        panel.message = "Select video files or folders (top-level scan only)."
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.resolvesAliases = true

        // Optional: keep the chooser focused on media-ish types, but still allow folders.
        // (If you find this too restrictive in practice, we can remove allowedContentTypes.)
        panel.allowedContentTypes = [.fileURL]

        panel.begin { response in
            defer { isShowingImportPanel = false }
            guard response == .OK else { return }
            state.importMedia(from: panel.urls, alertTitle: "Add Processing")
        }
    }
#endif


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
            let urls = Array(rawURLs)
            DispatchQueue.main.async {
                state.importMedia(from: urls, alertTitle: "Drop Processing")
            }
        }

        return accepted
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

private struct QueueList: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }
    
    private let missingSourceReason = "blocked: source item no longer available"

    private func isMissingSourceBlocked(_ item: MediaItem) -> Bool {
        item.status == .blocked && item.statusReason == missingSourceReason
    }

    private func suggestedURL(for item: MediaItem) -> URL {
        item.plannedOutputURL
            ?? item.finalOutputURL
            ?? OutputNamer.suggestedOutputURL(for: item.url, settings: state.settings)
    }
    
    @ViewBuilder
    private func rowView(for item: MediaItem) -> some View {
        UI_QueueRow(
            item: item,
            suggested: suggestedURL(for: item),
            isExpandedExternal: state.expandedRowIDs.contains(item.id),
            onToggleExpand: {
                if state.expandedRowIDs.contains(item.id) {
                    state.expandedRowIDs.remove(item.id)
                } else {
                    state.expandedRowIDs.insert(item.id)
                }
            },
            isQueuedExternal: item.isChecked,
            onToggleQueued: { newVal in
                guard item.status != .encoding else { return }
                guard let idx = AppCore.shared.index(of: item.id),
                      let refreshed = AppCore.shared.file(at: idx)
                else { return }

                // A2: prevent re-checking items blocked due to missing source
                if refreshed.status == .blocked,
                   refreshed.statusReason == "blocked: source item no longer available" {
                    return
                }

                switch refreshed.status {
                case .queued:
                    AppCore.shared.updateFile(at: idx) { file in
                        file.isChecked = newVal
                    }

                    if newVal, state.settings.autoEncodeOnDrop,
                       let again = AppCore.shared.file(at: idx),
                       again.status == .queued {
                        state.submit(items: [again])
                    }

                case .done, .error, .blocked:
                    guard newVal else { return }
                    AppCore.shared.requeueItem(item.id)

                    if state.settings.autoEncodeOnDrop,
                       let updated = AppCore.shared.file(at: idx),
                       updated.status == .queued,
                       updated.isChecked {
                        state.submit(items: [updated])
                    }

                case .encoding:
                    break
                }
            },
            onDelete: {
                AppCore.shared.removeItem(item.id)
                state.expandedRowIDs.remove(item.id)
            }
        )
        .environmentObject(state)
        .padding(.horizontal, StyleConstants.Spacing.panelPaddingV_expanded)
        .padding(.vertical, StyleConstants.Spacing.listRowVerticalPadding)
        .contentShape(Rectangle())
        .background(
            // Keep the selection highlight + tap-to-select behavior,
            // but do NOT steal taps from subcontrols (checkbox/chevron/buttons).
            ZStack {
                state.selectedIDs.contains(item.id)
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
        #if os(macOS)
                        if NSEvent.modifierFlags.contains(.command) {
                            state.toggleSelection(for: item.id)
                        } else {
                            state.selectedIDs = [item.id]
                        }
        #else
                        state.selectedIDs = [item.id]
        #endif
                    }
            }
        )
    }


    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(state.files, id: \.id) { item in
                rowView(for: item)

                if item.id != state.files.last?.id {
                    Divider()
                        .padding(.horizontal, StyleConstants.Spacing.panelPaddingV_expanded)
                }
            }
        }
        .padding(.vertical, StyleConstants.Spacing.panelSpacing)

        .onChange(of: state.settings.runMode) { newMode in
            if newMode == .remoteDeadline {
                // Validate sources for farm access; block and uncheck if not visible
                let files = AppCore.shared.filesSnapshot().map { ($0.id, $0.url) }
                for (id, srcURL) in files {
                    if case .failure(let error) = EncodeRenderfarm.isInputPathAcceptableForFarm(srcURL) {
                        AppCore.shared.updateFile(id: id) { file in
                            file.status = .blocked
                            file.statusReason = error.message
                            file.isChecked = false
                        }
                    }
                }
            } else if newMode == .localNative {
                // Switching back to Local: unblock and re-enable encode
                let ids = AppCore.shared.filesSnapshot().map { $0.id }
                for id in ids {
                    if let f = AppCore.shared.file(id: id), f.status == .blocked {
                        // Do NOT auto-unblock items blocked due to missing source.
                        guard f.statusReason != missingSourceReason else { continue }

                        AppCore.shared.updateFile(id: id) { file in
                            file.status = .queued
                            file.statusReason = nil
                            file.isChecked = true
                        }
                    }
                }
            }
        }

        .background(C.bgDropZone)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// UI_Queue.swift — tweak EmptyQueueView so it doesn't force top alignment

private struct EmptyQueueView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 28))
                //.opacity(0.6)

            Text("Drop QuickTime files or Folder here")
                .foregroundColor(StyleConstants.colors(for: colorScheme).textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}


private struct FloatingPlatterStyle: ViewModifier {
    let fill: Color
    let shadow: Color

    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(fill)
            )
            .shadow(color: shadow, radius: 4, x: 0, y: 4)
    }
}


private struct AutoEncodeFloatingButton: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var isOn: Bool { state.settings.autoEncodeOnDrop }
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    private var d: CGFloat { StyleConstants.Sizes.floatingButtonDiameter }

    var body: some View {
        Button {
            state.settings.autoEncodeOnDrop.toggle()
        } label: {
            ZStack {
                ZStack {
                    Image(systemName: "arrow.trianglehead.clockwise")
                        .renderingMode(.template)
                        .font(.system(size: 22, weight: .regular))
                        .offset(y: -1)

                    Image(systemName: "play.fill")
                        .renderingMode(.template)
                        .font(.system(size: 12, weight: .regular))
                        .offset(y: 0.5)
                }
                // OFF = constant token, ON = accent blue
                .foregroundColor(isOn ? C.accent : C.floatingControlIcon)
            }
            .frame(width: d, height: d)
            .modifier(FloatingPlatterStyle(fill: C.bgPlaybar, shadow: C.playbarShadow))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Auto Encode on Drop")
    }
}



private struct EncodePauseCancelFloatingGroup: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    private var d: CGFloat { StyleConstants.Sizes.floatingButtonDiameter }

    var body: some View {
        HStack(spacing: 10) {

            // Paused indicator (keep accent semantics, but use same token)
            if state.isGloballyPaused {
                let isPausing = state.files.contains { $0.status == .encoding }

                HStack(spacing: 6) {
                    Image(systemName: isPausing ? "pause.circle" : "pause.circle.fill")
                        .renderingMode(.template)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(C.floatingControlIcon)

                    Text(isPausing ? "Pausing..." : "Paused")
                        .font(.caption)
                        .foregroundColor(C.floatingControlIcon)
                }
                .padding(.trailing, 4)
            }

            groupButton(systemName: "play.fill",  help: "Start Encode", action: startEncode)
            groupButton(
                systemName: "pause.fill",
                help: state.isGloballyPaused
                    ? "Queue Paused (click Play to resume)"
                    : "Pause Queue (finishes current media first)",
                action: pauseEncode
            )
            groupButton(systemName: "stop.fill",  help: "Cancel Encode", action: cancelEncode)
        }
        .padding(.horizontal, 8)
        .frame(height: d)
        .background(
            Capsule(style: .continuous)
                .fill(C.bgPlaybar)
        )
        .shadow(color: C.playbarShadow, radius: 4, x: 0, y: 4)
        .fixedSize()
    }

    private func groupButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .renderingMode(.template)
                .font(.system(size: StyleConstants.Typography.queueControlIconSize,
                              weight: StyleConstants.Typography.queueControlIconWeight))
                .foregroundColor(C.floatingControlIcon)
                .frame(width: d, height: d)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func startEncode() {
        if state.isGloballyPaused {
            state.isGloballyPaused = false
            return
        }

        if state.settings.runMode == .remoteDeadline && !state.settings.deadlinePoolsValid {
            state.pushMessage(
                level: .warning,
                "Deadline encode blocked — you must set a Pool in Deadline Options first.",
                filename: nil,
                code: .farmPath,
                originKey: "encode"
            )
            return
        }

        let chosen = state.files.filter { $0.isChecked && $0.status == .queued }
        if chosen.isEmpty {
            state.pushMessage(level: .warning, "No media ready to encode", filename: nil)
            return
        }
        state.submit(items: chosen)
    }

    private func pauseEncode() {
        if !state.isGloballyPaused {
            state.isGloballyPaused = true
        }
    }

    private func cancelEncode() {
        state.cancelAllEncoding()
    }
}


private struct TrashFloatingButton: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    private var d: CGFloat { StyleConstants.Sizes.floatingButtonDiameter }

    var body: some View {
        Button {
            state.clearAll()
        } label: {
            Image(systemName: "trash.fill")
                .renderingMode(.template)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(C.floatingControlIcon)
                .frame(width: d, height: d)
                .modifier(FloatingPlatterStyle(fill: C.bgPlaybar, shadow: C.playbarShadow))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Clear All")
    }
}


