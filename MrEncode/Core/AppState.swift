//
// MARK: - AppState.swift (Revised - Removed footerHeight)
//

import Foundation
import SwiftUI
import Combine
import AVFoundation


/// UI state coordinator - delegates business logic to AppCore
@MainActor
final class AppState: ObservableObject {
    
    // MARK: - Preview support
    static let preview: AppState = {
        let state = AppState(previewMode: true)
        return state
    }()
    
    init(previewMode: Bool = false) {
        AppState.shared = self

        if !previewMode {
            core.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.objectWillChange.send()
                    }
                }
                .store(in: &cancellables)

            core.bootstrapDeadlineLists()
        }
    }

    
    // MARK: - Queue maintenance (UI convenience)
    func clearAll() {
        // Mirrors previous behavior: clear everything that isn't actively encoding
        clearAllNonEncoding()
    }
    
    // MARK: - Queue Keyboard Actions (Navigation)

    @Published var expandedRowIDs: Set<UUID> = []

    func removeSelectedQueueMedia() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        removeItems(withIDs: ids)
        selectedIDs = []
    }

    func selectNextQueueRow() {
        selectQueueRow(delta: +1)
    }

    func selectPreviousQueueRow() {
        selectQueueRow(delta: -1)
    }

    private func selectQueueRow(delta: Int) {
        guard !files.isEmpty else { return }

        let ordered = files.map { $0.id }

        // If nothing selected, pick first/last depending on direction
        guard let current = selectedIDs.first, let idx = ordered.firstIndex(of: current) else {
            selectedIDs = [delta >= 0 ? ordered.first! : ordered.last!]
            return
        }

        let newIndex = max(0, min(ordered.count - 1, idx + delta))
        selectedIDs = [ordered[newIndex]]
    }
    
    func expandSelectedQueueRow() {
        guard let id = selectedIDs.first else { return }
        expandedRowIDs.insert(id)
    }

    func collapseSelectedQueueRow() {
        guard let id = selectedIDs.first else { return }
        expandedRowIDs.remove(id)
    }

    func toggleExpandedForSelection() {
        guard let id = selectedIDs.first else { return }
        if expandedRowIDs.contains(id) {
            expandedRowIDs.remove(id)
        } else {
            expandedRowIDs.insert(id)
        }
    }

    
    // Allow non-UI helpers to update file statuses
    static weak var shared: AppState?
    
    // MARK: - Core Business Logic (Delegated)
    private let core = AppCore.shared
    
    // MARK: - UI-Specific State
    // REMOVED: @Published var footerHeight: CGFloat = 0  // No longer needed with new layout
    @Published var selectedIDs: Set<MediaItem.ID> = []
    @Published var showPreferences: Bool = false
    @Published var isRobotMode: Bool = false
    
    // MARK: - Delegated Core Properties
    var files: [MediaItem] { core.files }
    var settings: Settings {
        get { core.settings }
        set { core.settings = newValue }
    }
    var uiMessages: [AppLogEntry] { core.uiMessages }
    var deadlineAvailable: Bool { core.deadlineAvailable }
    var isRefreshingDeadline: Bool { core.isRefreshingDeadline }
    var deadlineError: String? { core.deadlineError }
    var didBootstrapDeadline: Bool { core.didBootstrapDeadline }
    var availablePresets: [EncodingPreset] { core.availablePresets }
    var isDropletMode: Bool { core.isDropletMode }
    var globalProgress: Double { core.globalProgress }
    var globalProgressText: String { core.globalProgressText }
    var isBackgroundProcessing: Bool { core.isBackgroundProcessing }
    var backgroundProgress: Double { core.backgroundProgress }
    
    // MARK: - Droplet / Ingest Helpers

    @MainActor
    func setIngestGroupID(_ ingestGroupID: String, forMediaIDs ids: Set<UUID>) {
        core.setIngestGroupID(ingestGroupID, forMediaIDs: ids)
    }
    
    // MARK: - Coalesced revalidation scheduler (prevents SwiftUI "Publishing during view update" faults)

    private var pendingRevalidateTask: Task<Void, Never>? = nil

    /// Safe to call from SwiftUI `onChange` without triggering "Publishing changes from within view updates..."
    func requestRevalidate() {
        pendingRevalidateTask?.cancel()

        pendingRevalidateTask = Task { @MainActor in
            // Small delay lets SwiftUI finish the current render pass
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            core.revalidateFilesForCurrentMode()
        }
    }
    
    // MARK: - Encoding Service Delegation
    
    private var pendingForwardTask: Task<Void, Never>?

    var isGloballyPaused: Bool {
        get { EncodingService.shared.isGloballyPaused }
        set { EncodingService.shared.isGloballyPaused = newValue }
    }
    
    init() {
        AppState.shared = self
        
        // Set up change propagation from core to UI
        core.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }

                self.pendingForwardTask?.cancel()
                self.pendingForwardTask = Task { @MainActor in
                    await Task.yield()   // get out of the current SwiftUI update pass
                    self.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
        
        // Initialize core
        core.bootstrapDeadlineLists()
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    
    // MARK: - File Management (Delegated)
    
    func addFiles(_ urls: [URL]) {
        core.addFiles(urls)
    }
    
    func removeItems(withIDs ids: Set<MediaItem.ID>) {
        core.removeItems(withIDs: ids)
    }
    
    func clearAllNonEncoding() {
        core.clearAllNonEncoding()
    }
    
    func revalidateFilesForCurrentMode() {
        core.revalidateFilesForCurrentMode()
    }
    
    func duplicateSelected() {
        core.duplicateItems(withIDs: selectedIDs)
    }
    
    
    func importQueue(from url: URL, mode: QueueImportMode) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let doc = try decoder.decode(QueueDocument.self, from: data)

                // Basic format/version guard
                guard doc.format == QueueDocument.formatID else {
                    throw QueueSaveError.invalidDocumentFormat(doc.format)
                }

                let fm = FileManager.default
                var imported: [MediaItem] = []
                imported.reserveCapacity(doc.items.count)

                var missingCount = 0

                for entry in doc.items {
                    let raw = entry.source.url.trimmingCharacters(in: .whitespacesAndNewlines)

                    let parsedURL: URL?
                    if raw.lowercased().hasPrefix("file://") {
                        parsedURL = URL(string: raw)
                    } else {
                        parsedURL = URL(fileURLWithPath: raw)
                    }

                    guard let u0 = parsedURL?.standardizedFileURL else {
                        // Treat unparseable as missing source row (blocked) so user can see it.
                        missingCount += 1
                        var item = MediaItem(url: URL(fileURLWithPath: "/"), meta: .empty, status: .blocked,
                                             statusReason: "blocked: source item no longer available")
                        item.isChecked = false
                        imported.append(item)
                        continue
                    }

                    var isDir: ObjCBool = false
                    let exists = fm.fileExists(atPath: u0.path, isDirectory: &isDir)

                    // Start with queued; then apply saved queue state.
                    var item = MediaItem(url: u0, meta: .empty, status: .queued, statusReason: nil)

                    // Restore checked/unchecked (default true for older queue docs)
                    let restoredChecked = entry.queue?.isChecked ?? true
                    item.isChecked = restoredChecked

                    // Restore status if present (optional). If absent, leave as queued.
                    if let savedStatus = entry.queue?.status,
                       let st = EncodeStatus(rawValue: savedStatus) {
                        item.status = st
                    }

                    // Restore statusReason if present
                    if let savedReason = entry.queue?.statusReason, !savedReason.isEmpty {
                        item.statusReason = savedReason
                    }

                    // Override: missing / directory source becomes Blocked + unchecked with required reason
                    if !exists || isDir.boolValue {
                        missingCount += 1
                        item.status = .blocked
                        item.isChecked = false
                        item.statusReason = "blocked: source item no longer available"
                    }

                    // If saved status is blocked, ensure unchecked even if older file had isChecked=true
                    if item.status == .blocked {
                        item.isChecked = false
                        if item.statusReason == nil || item.statusReason?.isEmpty == true {
                            item.statusReason = "blocked"
                        }
                    }

                    imported.append(item)
                }

                DispatchQueue.main.async {
                    // Replace vs append behavior matches your current import UX
                    switch mode {
                    case .replace:
                        let allIDs = Set(self.files.map { $0.id })
                        if !allIDs.isEmpty {
                            self.removeItems(withIDs: allIDs)
                        }
                        self.selectedIDs = []
                        AppCore.shared.appendImportedQueueItems(imported)

                    case .append:
                        AppCore.shared.appendImportedQueueItems(imported)
                    }

                    // User feedback
                    if imported.isEmpty {
                        self.pushMessage(level: .warning, "Queue import produced no media items.")
                    } else {
                        let blocked = imported.filter { $0.status == .blocked }.count
                        if blocked > 0 {
                            self.pushMessage(level: .warning, "Imported \(imported.count) media item(s) (\(blocked) blocked due to missing source).")
                        } else {
                            self.pushMessage(level: .info, "Imported \(imported.count) media item(s) from queue.")
                        }
                    }

                    // Ensure mode-based validation is applied after import
                    self.revalidateFilesForCurrentMode()
                }

            } catch {
                DispatchQueue.main.async {
                    self.pushMessage(level: .error, "Open Queue failed: \(error.localizedDescription)")
                }
            }
        }
    }

    
    
    // MARK: - Media Import (Unified pipeline)

    /// Unified import pipeline for any “bring media into the queue” entry point:
    /// drop, double-click import, File menu import, DZ context menu import.
    ///
    /// - Important: "media" here means files to be encoded (QuickTime).
    func importMedia(from urls: [URL], alertTitle: String = "Import Processing") {

        // Do folder scanning / filtering off the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            let result = QueueImportService.process(urls)

            DispatchQueue.main.async {
                self.applyImportResult(result, alertTitle: alertTitle)
            }
        }
    }

    /// Called by the "Add All" confirmation alert to commit the pending import.
    func confirmPendingImportMedia() {
        let candidates = AppCore.shared.pendingAddAfterConfirm
        guard !candidates.isEmpty else {
            AppCore.shared.showAmountConfirm = false
            return
        }

        AppCore.shared.pendingAddAfterConfirm = []
        AppCore.shared.showAmountConfirm = false

        finalizeImportedMedia(candidates)
    }

    // MARK: - Import helpers (UI-thread)

    private func applyImportResult(_ result: QueueImportResult, alertTitle: String) {

        // Existing modal warnings (folder scan / confirm messaging)
        if !result.warnings.isEmpty {
            AppCore.shared.folderAlertTitle = alertTitle
            AppCore.shared.folderAlertMessage = result.warnings.joined(separator: "\n\n")
            AppCore.shared.showFolderAlert = true
        }

        // New: non-modal notice for rejected files
        if !result.rejectedFilenames.isEmpty {
            let list = result.rejectedFilenames.count > 5
                ? result.rejectedFilenames.prefix(5).joined(separator: ", ")
                    + ", and \(result.rejectedFilenames.count - 5) more"
                : result.rejectedFilenames.joined(separator: ", ")

            AppCore.shared.pushMessage(
                level: .warning,
                "Skipped unsupported media: \(list)",
                originKey: "import"
            )
        }

        guard !result.candidates.isEmpty else { return }

        if result.requiresConfirm {
            AppCore.shared.pendingAddAfterConfirm = result.candidates
            AppCore.shared.showAmountConfirm = true
            return
        }

        finalizeImportedMedia(result.candidates)
    }

    
    // MARK: - Evenize check (moved from UI_Queue for reuse)

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
            pushMessage(
                level: .warning,
                "Non-even dims will be evenized: \(rawW)×\(rawH) → \(evenW)×\(evenH)",
                filename: url.lastPathComponent
            )
        } else if (srcW % 2 != 0 || srcH % 2 != 0) && factor == 1.0 {
            pushMessage(
                level: .warning,
                "Source has odd dims; output will be \(evenW)×\(evenH)",
                filename: url.lastPathComponent
            )
        }
    }


    private func finalizeImportedMedia(_ urls: [URL]) {

        // Add to queue
        addFiles(urls)

        // Keep behavior consistent with drop: kick auto-encode if enabled.
        if settings.autoEncodeOnDrop {
            submit()
        }

        // Post-add checks (consistent with prior UI_Queue behavior)
        for url in urls {
            sanityCheckEvenize(for: url, settings: settings)

            // Deadline-only safety — block only if SOURCE is not visible to the farm
            if settings.runMode == .remoteDeadline {
                if case .failure(let error) = EncodeRenderfarm.isInputPathAcceptableForFarm(url) {
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

    
    // MARK: - Selection Helper

    private var selectionAnchorID: MediaItem.ID? = nil

    func selectedItemsOrAll() -> [MediaItem] {
        selectedIDs.isEmpty ? files : files.filter { selectedIDs.contains($0.id) }
    }

    func selectAll() {
        let ids = files.map(\.id)
        selectedIDs = Set(ids)
        selectionAnchorID = ids.last
    }

    func selectNone() {
        selectedIDs.removeAll()
        selectionAnchorID = nil
    }

    // Cmd-click style toggle (sets anchor for subsequent Shift-click range selection)
    func toggleSelection(for id: MediaItem.ID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
        selectionAnchorID = id
    }

    // Normal click single selection (sets anchor)
    func selectSingle(_ id: MediaItem.ID) {
        selectedIDs = [id]
        selectionAnchorID = id
    }

    // Shift-click range selection (uses current queue order)
    func selectRange(to id: MediaItem.ID) {
        let orderedIDs = files.map(\.id)

        guard let anchor = selectionAnchorID,
              let a = orderedIDs.firstIndex(of: anchor),
              let b = orderedIDs.firstIndex(of: id)
        else {
            selectSingle(id)
            return
        }

        let lo = min(a, b)
        let hi = max(a, b)
        selectedIDs = Set(orderedIDs[lo...hi])
        // Keep anchor as-is (Finder-like); do not change selectionAnchorID here.
    }

    // MARK: - Encoding Operations (Delegated)
    
    func submit(items: [MediaItem]) {
        core.submit(items: items)
    }
    
    func submit() {
        // Only submit items that are READY and CHECKED, in ALL modes.
        let itemsToSubmit = files.filter { $0.status == .queued && $0.isChecked }
        guard !itemsToSubmit.isEmpty else { return }
        submit(items: itemsToSubmit)
    }
    
    func cancelAllEncoding() {
        core.cancelAllEncoding()
    }
    
    func pauseResumeAll() {
        isGloballyPaused.toggle()
    }
    
    // MARK: - Status Updates (Delegated)
    //
    // These exist specifically so non-UI helpers that currently call AppState.shared
    // can update item state WITHOUT bypassing AppCore’s batch-completion logic.

    func setStatus(_ status: EncodeStatus, forIndex index: Int) {
        core.setStatus(status, forIndex: index)
    }

    func markEncoding(itemID: UUID) {
        core.markEncoding(itemID: itemID)
    }

    func markFinished(itemID: UUID, outputURL: URL) {
        core.markFinished(itemID: itemID, outputURL: outputURL)
    }

    func markError(itemID: UUID, reason: String?) {
        core.markError(itemID: itemID, reason: reason)
    }

    // MARK: - UI Messages (Delegated)
    
    func pushMessage(level: LogLevel, _ text: String, filename: String? = nil, code: LogCode? = nil, originKey: String? = nil, detail: String? = nil, jobID: String? = nil, logURL: URL? = nil) {
        core.pushMessage(level: level, text, filename: filename, code: code, originKey: originKey, detail: detail, jobID: jobID, logURL: logURL)
    }
    
    // MARK: - Deadline Operations (Delegated)
    
    func refreshDeadlineData() {
        core.refreshDeadlineOptions(inBackground: false)
    }
    
    func refreshDeadlineOptions(inBackground: Bool = false) {
        core.refreshDeadlineOptions(inBackground: inBackground)
    }
    
    func bootstrapDeadlineLists() {
        core.bootstrapDeadlineLists()
    }
    
    // MARK: - Preset Management (Delegated)
    
    func loadPresets() {
        core.loadPresets()
    }
    
    func applyPreset(name: String) {
        core.applyPreset(name: name)
        // Re-inject machine-local sticky pools if the preset left them blank/none
        settings = PreferencesService.shared.applyStickyDeadlineFallback(to: settings)
    }
    
    func savePreset(name: String) throws {
        try core.saveCurrentAsPreset(name: name)
    }
    
    func loadPreset(name: String) {
        core.applyPreset(name: name)
    }

    func resetPreferencesToFactoryDefaults() {
        let defaults = PreferencesService.shared.resetSettingsToFactoryDefaults()
        core.settings = defaults
        core.bootstrapDeadlineLists()
        pushMessage(level: .info, "Restored preferences to factory defaults")
    }
    
    func deletePreset(name: String) throws {
        try core.deletePreset(name: name)
    }
    
    func exportPreset(name: String, to url: URL) {
        // This functionality is handled by exportDroplet
        core.exportDroplet(name: name)
    }
    
    func importPreset(from url: URL) -> (success: Bool, presetName: String?) {
        // This would need to be implemented in AppCore if needed
        // For now, return a placeholder
        return (false, nil)
    }
    
    func createDroplet(presetName: String, to url: URL) {
        core.exportDroplet(name: presetName)
    }
    
    // MARK: - Droplet Support (Delegated)
    
    func enableDropletMode(presetName: String, exitWhenDone: Bool) {
        core.enableDropletMode(presetName: presetName, exitWhenDone: exitWhenDone)
    }
    
    func exportDroplet(name: String) {
        let baseSettings: Settings
        if let preset = availablePresets.first(where: { $0.name == name }) {
            baseSettings = preset.settings
        } else {
            baseSettings = settings
        }

        presentDropletExporter(presetName: name, baseSettings: baseSettings)
    }

    func exportCurrentSettingsAsDroplet() {
        let name = settings.selectedPresetName.isEmpty ? "Custom" : settings.selectedPresetName
        presentDropletExporter(presetName: name, baseSettings: settings)
    }

    private func presentDropletExporter(presetName: String, baseSettings: Settings) {
        var dropletSettings = PreferencesService.shared.applyStickyDeadlineFallback(to: baseSettings)

        if dropletSettings.runMode == .remoteDeadline {
            let prefs = PreferencesService.shared
            func resolved(_ primary: String, _ secondary: String, _ sticky: String) -> String {
                let trimmedPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedPrimary.isEmpty, trimmedPrimary.lowercased() != "none" {
                    return primary
                }
                let trimmedSecondary = secondary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedSecondary.isEmpty, trimmedSecondary.lowercased() != "none" {
                    return secondary
                }
                let trimmedSticky = sticky.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedSticky.isEmpty, trimmedSticky.lowercased() != "none" {
                    return sticky
                }
                return ""
            }

            dropletSettings.pool = resolved(baseSettings.pool, dropletSettings.pool, prefs.stickyPool)
            dropletSettings.secondaryPool = resolved(baseSettings.secondaryPool, dropletSettings.secondaryPool, prefs.stickySecondaryPool)
            dropletSettings.group = resolved(baseSettings.group, dropletSettings.group, prefs.stickyGroup)
        }


        if dropletSettings.runMode == .remoteDeadline && !dropletSettings.deadlinePoolsValid {
            pushMessage(
                level: .warning,
                "Cannot export a Deadline droplet — set a Pool in the Deadline Options panel first.",
                filename: nil,
                code: .farmPath,
                originKey: "export-droplet"
            )
            return
        }

        var exportSettings = dropletSettings.forDroplet()
        if exportSettings.runMode == .remoteDeadline {
            if exportSettings.pool.isNoneOrEmpty {
                exportSettings.pool = dropletSettings.pool
            }
            if exportSettings.secondaryPool.isNoneOrEmpty {
                exportSettings.secondaryPool = dropletSettings.secondaryPool
            }
            if exportSettings.group.isNoneOrEmpty {
                exportSettings.group = dropletSettings.group
            }
        }

        DropletBuilder.shared.showCreateDropletDialog(
            presetName: presetName,
            settings: exportSettings
        ) { _ in }
    }

    
    // MARK: - Validation (Delegated)
    
    func validateCurrentSettings() -> (isValid: Bool, message: String?) {
        // This would need to be implemented in AppCore if needed
        // For now, return a basic validation
        return (true, nil)
    }
    
    // MARK: - CLI Mode Support
    
    func configureForDropletMode() {
        // This functionality is handled by enableDropletMode
        core.enableDropletMode(presetName: settings.selectedPresetName, exitWhenDone: true)
    }
    
    func processDropletFiles(_ urls: [URL], presetPath: String) {
        // Add files and auto-encode if droplet mode is enabled
        addFiles(urls)
    }
    
    // MARK: - Temp File Management (Delegated)
    
    func cleanupTempOutput(for itemID: UUID) {
        core.cleanupTempOutput(for: itemID)
    }
    
    @MainActor
    func setTempOutput(_ url: URL?, for itemID: UUID) {
        core.setTempOutput(url, for: itemID)
    }
}

extension AppState {

    private func selectedPresetSettings() -> Settings? {
        let name = settings.selectedPresetName
        return availablePresets.first(where: { $0.name == name })?.settings
    }

    func isPanelModified(_ panel: Settings.PanelID) -> Bool {
        let name = settings.selectedPresetName
        guard
            let preset = availablePresets.first(where: { $0.name == name }),
            let raw = preset.rawSettings
        else {
            return false
        }
        return settings.isPanelModified(panel, baselineRaw: raw)
    }
}
