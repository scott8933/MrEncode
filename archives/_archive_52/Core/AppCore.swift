//
//  AppCore.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/23/25.
//

//
// MARK: - AppCore.swift
//

import Foundation
import SwiftUI
import Combine

/// Core business logic separated from UI state
class AppCore: ObservableObject {
    static let shared = AppCore()
    
    // MARK: - Published Core State
    @Published var files: [MediaItem] = []
    @Published var settings: Settings {
        didSet {
            PreferencesService.shared.saveSettings(settings)
        }
    }
    
    // MARK: - Background Media Inspection (Metadata + Probe Warm-Up)

    /// Cancel and discard background inspection tasks for the given item IDs.
    private func cancelInspections(for ids: Set<UUID>) {
        for id in ids {
            inspectTasks[id]?.cancel()
            inspectTasks[id] = nil
            inspectGeneration[id] = nil
        }
    }

    private var inspectTasks: [UUID: Task<Void, Never>] = [:]
    private var inspectGeneration: [UUID: Int] = [:]
    
    // MARK: - Alerts for Drag and Drop
    @Published var showFolderAlert = false
    @Published var folderAlertTitle = ""
    @Published var folderAlertMessage = ""
    @Published var showAmountConfirm = false
    @Published var pendingAddAfterConfirm: [URL] = []
    
    // MARK: - Services
    private let metadataService = MetadataService.shared
    private let validationService = ValidationService.shared
    private let encodingService = EncodingService.shared
    private let fileService = FileManagementService.shared
    
    // MARK: - Logging
    @Published var uiMessages: [AppLogEntry] = []
    
    // MARK: - Deadline
    @Published var deadlineAvailable: Bool = false
    @Published var isRefreshingDeadline: Bool = false
    @Published var deadlineError: String?
    @Published var didBootstrapDeadline: Bool = false
    
    // MARK: - Preset Support
    @Published var availablePresets: [EncodingPreset] = []
    @Published var isDropletMode: Bool = false
    private var dropletExitWhenDone: Bool = false
    
    // MARK: - Batch Completion Chime
    private var didSubmitBatchEncode: Bool = false
    private var didPlayBatchDoneChime: Bool = false
    
    private init() {
        self.settings = PreferencesService.shared.loadSettings()
        loadPresets()
        // Kick off initial Deadline probe (non-blocking)
        DispatchQueue.main.async { [weak self] in
            self?.bootstrapDeadlineLists()
        }
    }
    
    // MARK: - File Management
    
    func addFiles(_ urls: [URL]) {
        // Deduplication: filter out URLs already in queue
        let newUrls = urls.filter { url in
            !files.contains { $0.url == url }
        }
        
        guard !newUrls.isEmpty else {
            print("⚠️ All URLs already in queue, ignoring")
            return
        }
        
        let startIndex = files.count
        
        // First pass: Add items immediately with minimal blocking work
        for url in newUrls {  // ← Use newUrls instead of urls
            var item = MediaItem(
                url: url,
                meta: .empty,
                status: .queued,
                statusReason: nil
            )

            // Only do minimal synchronous checks needed for UI
            if settings.runMode == .remoteDeadline {
                if case .failure(let error) = EncodeRemote.isInputPathAcceptableForFarm(url) {
                    item.status = .blocked
                    item.statusReason = error.message
                    item.isChecked = false
                    pushMessage(level: .warning,
                               "Blocked: \(url.lastPathComponent) — \(error.message)",
                               filename: url.lastPathComponent,
                               code: .farmPath,
                               originKey: "add-files")
                }
            }

            files.append(item)
        }

        // Second pass: Start per-item background inspection (metadata + optional probe warm-up).
        // This centralizes all inspection policy in the model layer (not SwiftUI).
        for url in newUrls {
            if let item = self.files.first(where: { $0.url == url }) {
                Task { @MainActor in
                    self.startInspection(for: item.id)
                }
            }
        }

        // Revalidate immediately after initial add (blocked status, etc.)
        // Metadata-driven validation will refresh again as inspections complete.
        self.revalidateFilesForCurrentMode()
    }

    // MARK: - Background Media Inspection (Metadata + Probe Warm-Up)

    /// Starts (or restarts) background inspection for a queued item.
    /// Ownership: model-layer only (no SwiftUI code should probe media directly).
    /// Behavior:
    /// - Cancels any prior inspection task for this item id.
    /// - Extracts metadata off-main (AVFoundation/ExifTool work is never done in SwiftUI).
    /// - Optionally warms the MediaProbeService cache (deduped + cancellable).
    /// - Commits results on the main thread only if the task is still current.
    @MainActor
    func startInspection(for id: UUID) {
        // Cancel any existing inspection task for this id
        inspectTasks[id]?.cancel()

        // Invalidate any in-flight completion with a generation token
        let gen = (inspectGeneration[id] ?? 0) + 1
        inspectGeneration[id] = gen

        // Snapshot required inputs on main (avoid racing published state)
        guard let item = self.file(id: id) else { return }
        let url = item.url
        let scale = self.settings.scale

        // Mark as processing immediately so UI can show "Processing..."
        if let index = self.files.firstIndex(where: { $0.id == id }) {
            self.updateFile(at: index) { file in
                file.isProcessingMetadata = true
            }
        }

        inspectTasks[id] = Task(priority: .utility) { [weak self] in
            guard let self else { return }

            // 1) Extract metadata off-main
            let metadata = MetadataExtractor.extract(for: url)
            guard !Task.isCancelled else { return }

            // 2) Warm MediaProbeService cache (deduped). Do not block encode correctness.
            let probeTask = await MediaProbeService.shared.probeBasics(url: url, meta: metadata, scale: scale)
            _ = await probeTask.value
            guard !Task.isCancelled else { return }

            // 3) Commit results on main, only if still current
            await MainActor.run {
                guard self.inspectGeneration[id] == gen else { return }
                guard let index = self.files.firstIndex(where: { $0.id == id }) else { return }

                self.updateFile(at: index) { file in
                    file.meta = metadata
                    file.isProcessingMetadata = false

                    // Cache file size (model-owned; avoids UI doing filesystem calls)
                    if let size = self.fileService.getFileSize(for: url) {
                        file.setCachedFileSize(size)
                    }

                    // Rebuild cached display strings now that metadata is available
                    let srcLine = self.fileService.buildCachedSrcLine(for: file)
                    let dstLine = self.fileService.buildCachedDstLine(for: file, settings: self.settings, runMode: self.settings.runMode)
                    file.setCachedSrcLine(srcLine)
                    file.setCachedDstLine(dstLine)
                }

                // Validation depends on metadata (fps, duration, etc.)
                self.revalidateFilesForCurrentMode()
            }
        }
    }

    
    /// Remove items that aren't currently encoding
    func removeItems(withIDs ids: Set<MediaItem.ID>) {
        cancelInspections(for: ids)

        files.removeAll { item in
            ids.contains(item.id) && item.status != .encoding
        }
    }
    
    /// Clear everything except encoding items
    func clearAllNonEncoding() {
        let idsToRemove = Set(files.filter { $0.status != .encoding }.map { $0.id })
        cancelInspections(for: idsToRemove)

        files.removeAll { $0.status != .encoding }
    }

    @MainActor
    func removeItems(_ ids: Set<UUID>) {
        cancelInspections(for: ids)
        files.removeAll { ids.contains($0.id) }
    }

    @MainActor
    func removeItem(_ id: UUID) {
        removeItems([id])
    }

    
    // MARK: - Validation
    
    func revalidateFilesForCurrentMode() {
        for i in files.indices {
            validationService.validateItem(&files[i], settings: settings)
        }
        
        // Check for validation summary and auto-acknowledge resolved errors
        let summary = validationService.getValidationSummary(for: files, settings: settings)
        autoAcknowledgeResolvedErrors(summary: summary)
    }
    
    private func autoAcknowledgeResolvedErrors(summary: (anyFarmBlocked: Bool, anyNoOpBlocked: Bool, anyOverwriteBlocked: Bool, anyPoolBlocked: Bool)) {
        // Auto-acknowledge error categories that are now resolved
        for i in uiMessages.indices {
            let msg = uiMessages[i]
            if msg.acknowledged { continue }
            
            if let code = msg.code {
                switch code {
                case .farmPath where !summary.anyFarmBlocked:
                    uiMessages[i].acknowledged = true
                case .noOp where !summary.anyNoOpBlocked:
                    uiMessages[i].acknowledged = true
                case .wouldOverwrite where !summary.anyOverwriteBlocked:
                    uiMessages[i].acknowledged = true  
                case .other where !summary.anyPoolBlocked && msg.message.contains("pool"):
                    uiMessages[i].acknowledged = true
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - Encoding Operations
    
    func submit(items: [MediaItem]) {
        guard !items.isEmpty else { return }

        // STEP 6.4 — Silent abort of background inspection / probing
        // Only keep inspection work for items that are about to encode.
        let encodingIDs = Set(items.map { $0.id })
        let allInspectingIDs = Set(inspectTasks.keys)
        let idsToCancel = allInspectingIDs.subtracting(encodingIDs)
        cancelInspections(for: idsToCancel)

        // Cancel probe warm-ups for non-encoding URLs
        let encodingURLs = Set(items.map { $0.url })
        Task {
            await MediaProbeService.shared.cancelAllProbes(except: encodingURLs)
        }

        // New batch run (one-shot chime resets here)
        didSubmitBatchEncode = true
        didPlayBatchDoneChime = false

        // Re-queue any finished/blocked/error items so they can run again (overwrite)
        for id in items.map({ $0.id }) {
            if let idx = files.firstIndex(where: { $0.id == id }) {
                switch files[idx].status {
                case .done, .error, .blocked:
                    updateFile(at: idx) { file in
                        file.status = .queued
                        file.statusReason = nil
                    }
                default:
                    break
                }
            }
        }

        // Submit to encoding service
        encodingService.submitItems(items, settings: settings) { [weak self] itemID, status, reason in
            DispatchQueue.main.async {
                self?.updateItemStatus(itemID: itemID, status: status, reason: reason)
            }
        }
    }

    
    func cancelAllEncoding() {
        encodingService.cancelAllEncoding()
    }
    
    // MARK: - Status Updates

    func markEncoding(itemID: UUID) {
        updateFile(id: itemID) { file in
            file.status = .encoding
            file.statusReason = nil
        }
    }

    func markFinished(itemID: UUID, outputURL: URL) {
        updateFile(id: itemID) { file in
            file.finalOutputURL = outputURL
            file.status = .done
            file.statusReason = nil
        }
        checkDropletExit()
        checkBatchDoneChime()
    }

    func markError(itemID: UUID, reason: String?) {
        updateFile(id: itemID) { file in
            file.status = .error
            file.statusReason = reason
        }
        checkDropletExit()
        checkBatchDoneChime()
    }
    
    @MainActor
    func localEncodeDidComplete(itemID: UUID,
                                outputURL: URL?,
                                errorText: String?,
                                encodeSeconds: TimeInterval?) {

        guard let idx = files.firstIndex(where: { $0.id == itemID }) else { return }

        if let outputURL {
            files[idx].finalOutputURL = outputURL
            files[idx].status = .done
            files[idx].statusReason = nil
            files[idx].actualEncodeSeconds = encodeSeconds
            files[idx].isChecked = false
        } else {
            files[idx].status = .error
            files[idx].statusReason = errorText ?? "Local encode failed"
        }

        files[idx].progress = nil
        files[idx].etaSeconds = nil
        files[idx].progressMode = .none

        checkDropletExit()
        checkBatchDoneChime()
    }


    private func updateItemStatus(itemID: UUID, status: EncodeStatus, reason: String?) {
        updateFile(id: itemID) { file in
            file.status = status
            file.statusReason = reason
        }

        if status == .done || status == .error {
            checkDropletExit()
            checkBatchDoneChime()
        }
    }

    // MARK: - File Mutation Helper

    func updateFile(id: UUID, mutate: (inout MediaItem) -> Void) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        updateFile(at: index, mutate)
    }

    func updateFile(at index: Int, _ mutate: (inout MediaItem) -> Void) {
        guard files.indices.contains(index) else { return }
        precondition(Thread.isMainThread, "AppCore.updateFile must be called on the main thread")

        var copy = files[index]
        mutate(&copy)
        files[index] = copy
    }

    func index(of id: UUID) -> Int? {
        precondition(Thread.isMainThread, "AppCore.index(of:) must be called on the main thread")
        return files.firstIndex { $0.id == id }
    }

    func file(at index: Int) -> MediaItem? {
        precondition(Thread.isMainThread, "AppCore.file(at:) must be called on the main thread")
        guard files.indices.contains(index) else { return nil }
        return files[index]
    }

    func file(id: UUID) -> MediaItem? {
        precondition(Thread.isMainThread, "AppCore.file(id:) must be called on the main thread")
        return files.first { $0.id == id }
    }

    func file(matchingURL url: URL) -> MediaItem? {
        precondition(Thread.isMainThread, "AppCore.file(matchingURL:) must be called on the main thread")
        let target = url.standardizedFileURL
        return files.first { $0.url.standardizedFileURL == target }
    }

    func filesSnapshot() -> [MediaItem] {
        precondition(Thread.isMainThread, "AppCore.filesSnapshot() must be called on the main thread")
        return files
    }
    
    func setStatus(_ status: EncodeStatus, forIndex index: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.updateFile(at: index) { file in
                file.status = status
            }

            // Keep droplet behavior consistent
            self.checkDropletExit()

            // Critical: If any code path uses setStatus() to finish items,
            // we must still evaluate batch completion.
            if status == .done || status == .error {
                self.checkBatchDoneChime()
            }
        }
    }

    
    // MARK: - Estimates
    
    func estimateTotalEncodeSeconds() -> (seconds: Double, count: Int) {
        var total: Double = 0
        var n: Int = 0
        for item in files {
            guard item.isChecked, item.status == .queued else { continue }
            if let secs = EncodeTimeEstimator.estimateSeconds(
                basics: nil,
                meta: item.meta,
                settings: settings,
                runMode: settings.runMode),
               secs.isFinite, secs > 0 {
                total += secs
                n += 1
            }
        }
        return (total, n)
    }

    func formatHMS(_ secs: Double) -> String {
        guard secs.isFinite, secs > 0 else { return "0:00" }
        let t = Int(round(secs))
        let h = t / 3600, m = (t % 3600) / 60, s = (t % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                      : String(format: "%d:%02d", m, s)
    }
    
    // MARK: - Global Progress
    
    var globalProgress: Double {
        let activeItems = files.filter { $0.status == .encoding }
        guard !activeItems.isEmpty else { return 0.0 }
        
        let progressValues = activeItems.compactMap { $0.progress }
        guard !progressValues.isEmpty else { return 0.0 }
        
        return progressValues.reduce(0.0, +) / Double(progressValues.count)
    }
    
    var globalProgressText: String {
        let encoding = files.filter { $0.status == .encoding }.count
        let queued = files.filter { $0.status == .queued && $0.isChecked }.count
        
        if encoding > 0 {
            return "\(encoding) encoding" + (queued > 0 ? ", \(queued) queued" : "")
        } else if queued > 0 {
            return "\(queued) queued"
        } else {
            return "Ready"
        }
    }
    
    // MARK: - Background Processing Delegates
    
    var isBackgroundProcessing: Bool {
        metadataService.isBackgroundProcessing
    }
    
    var backgroundProgress: Double {
        metadataService.backgroundProgress
    }
    
    // MARK: - Logging
    
    func pushMessage(level: LogLevel,
                     _ message: String,
                     filename: String? = nil,
                     code: LogCode? = nil,
                     originKey: String? = nil,
                     detail: String? = nil,
                     jobID: String? = nil,
                     logURL: URL? = nil) {
        let entry = AppLogEntry(
            date: Date(),
            level: level,
            message: message,
            filename: filename,
            code: code,
            originKey: originKey,
            acknowledged: false,
            logURL: logURL,
            detail: detail,
            jobID: jobID
        )
        uiMessages.append(entry)
        if uiMessages.count > 5 { 
            uiMessages.removeFirst(uiMessages.count - 5) 
        }
    }
    
    // MARK: - Preset Management
    
    func loadPresets() {
        availablePresets = PresetManager.shared.loadPresets()
        
        // Ensure selected preset exists
        if !availablePresets.contains(where: { $0.name == settings.selectedPresetName }) {
            settings.selectedPresetName = "Good Quality - Local"
        }
    }
    
    func applyPreset(name: String) {
        guard let preset = availablePresets.first(where: { $0.name == name }) else {
            print("⚠️ Preset '\(name)' not found")
            return
        }
        
        settings.applyPreset(preset.settings, presetName: name)
        revalidateFilesForCurrentMode()
        pushMessage(level: .info, "Applied preset '\(name)'")
    }
    
    func saveCurrentAsPreset(name: String) throws {
        try PresetManager.shared.savePreset(name: name, settings: settings)
        loadPresets()
        settings.selectedPresetName = name
        pushMessage(level: .info, "Saved preset '\(name)'")
    }
    
    func deletePreset(name: String) throws {
        guard name != "Default" else {
            throw PresetError.invalidName("Cannot delete Default preset")
        }
        
        try PresetManager.shared.deletePreset(name: name)
        loadPresets()
        
        // If we deleted the current preset, switch to Default
        if settings.selectedPresetName == name {
            applyPreset(name: "Good Quality - Local")
        }
        
        pushMessage(level: .info, "Deleted preset '\(name)'")
    }
    
    // MARK: - Droplet Support
    
    func enableDropletMode(presetName: String, exitWhenDone: Bool) {
        isDropletMode = true
        dropletExitWhenDone = exitWhenDone
        settings.autoEncodeOnDrop = true
        
        // Apply the preset if it exists
        if let preset = availablePresets.first(where: { $0.name == presetName }) {
            settings.applyPreset(preset.settings, presetName: presetName)
        }
    }
    
    func exportDroplet(name: String) {
        let panel = NSSavePanel()
        panel.title = "Export Droplet"
        panel.nameFieldStringValue = "\(name).mrhevc"
        panel.allowedFileTypes = ["mrhevc"]
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let dropletSettings = settings.forDroplet()
                let droplet = DropletFile(presetName: name, settings: dropletSettings)
                let data = try JSONEncoder().encode(droplet)
                try data.write(to: url)
                pushMessage(level: .info, "Exported droplet '\(name)'")
            } catch {
                pushMessage(level: .error, "Failed to export droplet: \(error.localizedDescription)")
            }
        }
    }
    
    private func checkDropletExit() {
        guard isDropletMode, dropletExitWhenDone else { return }
        
        let hasActiveOrQueued = files.contains { item in
            item.status == .encoding || (item.status == .queued && item.isChecked)
        }
        
        if !hasActiveOrQueued && !files.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    private func checkBatchDoneChime() {
        NSLog("MrHEVC checkBatchDoneChime: entered didSubmit=\(didSubmitBatchEncode) didPlay=\(didPlayBatchDoneChime) files=\(files.count)")

        guard didSubmitBatchEncode, !didPlayBatchDoneChime else { return }
        guard !files.isEmpty else { return }

        let active = files.filter { $0.status == .encoding }
        let queuedChecked = files.filter { $0.status == .queued && $0.isChecked }

        NSLog("MrHEVC checkBatchDoneChime: active=\(active.count) queuedChecked=\(queuedChecked.count)")

        let hasActiveOrQueued = !active.isEmpty || !queuedChecked.isEmpty
        guard !hasActiveOrQueued else { return }

        NSLog("MrHEVC checkBatchDoneChime: TRIGGERING CHIME")

        didPlayBatchDoneChime = true
        didSubmitBatchEncode = false

        Task { @MainActor in
            SoundManager.shared.playDoneChime()
        }
    }


    
    // MARK: - Deadline Support
    
    func bootstrapDeadlineLists() {
        // Use cached lists immediately
        self.deadlineAvailable = !settings.poolOptions.isEmpty
        self.didBootstrapDeadline = true
        
        // Then refresh in background
        refreshDeadlineOptions(inBackground: true)
    }
    
    func refreshDeadlineOptions(inBackground: Bool = false) {
        guard !isRefreshingDeadline else { return }
        isRefreshingDeadline = true
        deadlineError = nil
        
        let dlCmd = settings.deadlineCommandPath.isEmpty
            ? (EncodeRemote.detectDeadlineCommand()
               ?? "/Applications/Thinkbox/Deadline10/Resources/deadlinecommand")
            : settings.deadlineCommandPath

        print("🔍 Using Deadline command path: \(dlCmd)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try EncodeRemote.fetchLists(
                    deadlineCmd: dlCmd
                )
                
                DispatchQueue.main.async {
                    self.isRefreshingDeadline = false
                    
                    // Success - we got results back
                    self.settings.poolOptions = result.pools
                    self.settings.groupOptions = result.groups
                    self.deadlineAvailable = !result.pools.isEmpty
                    self.deadlineError = nil
                    
                    self.settings.coerceDropdownDefaultsTopFirst()
                    
                    if self.deadlineAvailable {
                        self.pushMessage(level: .info, "Deadline connection successful")
                    } else {
                        self.pushMessage(level: .warning, "Deadline unavailable: No pools found")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isRefreshingDeadline = false
                    self.deadlineAvailable = false
                    self.deadlineError = error.localizedDescription
                    self.pushMessage(level: .warning,
                                   "Deadline unavailable: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Temp File Management
    
    func cleanupTempOutput(for itemID: UUID) {
        if let item = files.first(where: { $0.id == itemID }),
           let url = item.tempOutputURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    func setTempOutput(_ url: URL?, for itemID: UUID) {
        if let idx = files.firstIndex(where: { $0.id == itemID }) {
            files[idx].tempOutputURL = url
        }
    }
}

