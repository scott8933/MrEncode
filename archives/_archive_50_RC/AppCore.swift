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

        // Second pass: Extract metadata in background
        metadataService.extractMetadataForFiles(newUrls) { [weak self] results in  // ← Use newUrls directly
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Update items with extracted metadata
                for (url, metadata) in results {
                    if let index = self.files.firstIndex(where: { $0.url == url }) {
                        self.updateFile(at: index) { file in
                            file.meta = metadata
                            file.isProcessingMetadata = false

                            if let size = self.fileService.getFileSize(for: url) {
                                file.setCachedFileSize(size)
                            }

                            let srcLine = self.fileService.buildCachedSrcLine(for: file)
                            let dstLine = self.fileService.buildCachedDstLine(for: file, settings: self.settings)

                            file.setCachedSrcLine(srcLine)
                            file.setCachedDstLine(dstLine)
                        }
                    }
                }
                
                // Revalidate after metadata extraction
                self.revalidateFilesForCurrentMode()
            }
        }
    }
    
    /// Remove items that aren't currently encoding
    func removeItems(withIDs ids: Set<MediaItem.ID>) {
        files.removeAll { item in
            ids.contains(item.id) && item.status != .encoding
        }
    }
    
    /// Clear everything except encoding items
    func clearAllNonEncoding() {
        files.removeAll { $0.status != .encoding }
    }
    
    @MainActor
    func removeItems(_ ids: Set<UUID>) {
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
    }

    func markError(itemID: UUID, reason: String?) {
        updateFile(id: itemID) { file in
            file.status = .error
            file.statusReason = reason
        }
        checkDropletExit()
    }

    private func updateItemStatus(itemID: UUID, status: EncodeStatus, reason: String?) {
        updateFile(id: itemID) { file in
            file.status = status
            file.statusReason = reason
        }

        if status == .done || status == .error {
            checkDropletExit()
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
            self.checkDropletExit()
        }
    }
    
    // MARK: - Estimates
    
    func estimateTotalEncodeSeconds() -> (seconds: Double, count: Int) {
        var total: Double = 0
        var n: Int = 0
        for item in files {
            guard item.isChecked, item.status == .queued else { continue }
            if let secs = EncodeTimeEstimator.estimateSeconds(
                url: item.url,
                meta: item.meta,
                settings: settings,
                runMode: settings.runMode
            ), secs.isFinite, secs > 0 {
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
