//
//  AppCore.swift
//  MrEncode
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
    
    private var namingRefreshTask: Task<Void, Never>?
    private let namingRefreshDebounceNs: UInt64 = 120_000_000 // 120ms

    
    @MainActor
    private func scheduleNamingRefresh(reason: NamingChangeReason) {
        namingRefreshTask?.cancel()
        namingRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: namingRefreshDebounceNs)
            self.applyNamingChangeToQueue(reason: reason)
        }
    }

    
    // MARK: - Published Core State
    @Published var files: [MediaItem] = []
    @Published var settings: Settings {
        didSet {
            let old = oldValue
            PreferencesService.shared.saveSettings(settings)

            // Naming-affecting fields (expand this list as you add more naming rules)
            if old.outputSuffix != settings.outputSuffix ||
               old.nclcFilenameLabel != settings.nclcFilenameLabel ||
               old.nclcTag != settings.nclcTag ||
               old.containerFormat != settings.containerFormat {   // if this exists in Settings
                Task { @MainActor in
                    self.scheduleNamingRefresh(reason: .suffixChanged)
                }
            }
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

    // CLI/runtime override (does not persist to prefs)
    private var suppressBatchDoneChime: Bool = false

    private func applyRuntimeAudioFlags(_ flags: RuntimeFlags, arguments: [String]) {
        suppressBatchDoneChime = flags.suppressChime

        if suppressBatchDoneChime {
            NSLog("MrEncode: Batch done chime suppressed via CLI flag (args=\(arguments))")
        }
    }

    
    private init() {
        self.settings = PreferencesService.shared.loadSettings()

        // Apply CLI/runtime flags (GUI, droplet, and --cli all pass through here)
        let flags = RuntimeFlags.current
        applyRuntimeAudioFlags(flags, arguments: CommandLine.arguments)

        loadPresets()
        DispatchQueue.main.async { [weak self] in
            self?.bootstrapDeadlineLists()
        }
    }

    
    // MARK: - File Management
    
    @MainActor
    func addFiles(_ urls: [URL]) {
        // Queue rows are jobs. Allow same source URL to be added multiple times.
        // Only dedupe within this drop/add batch (avoid double-load from providers).
        let newUrls = Array(Set(urls.map { $0.standardizedFileURL }))

        guard !newUrls.isEmpty else { return }

        
        // First pass: Add items immediately with minimal blocking work
        for url in newUrls {
            var item = MediaItem(
                url: url,
                meta: .empty,
                status: .queued,
                statusReason: nil
            )

            // Only do minimal synchronous checks needed for UI
            if settings.runMode == .remoteDeadline {
                if case .failure(let error) = EncodeRenderfarm.isInputPathAcceptableForFarm(url) {
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
            
            // Admission-time destination allocation with overlay-aware logic
            let base = OutputNamer.suggestedOutputURL(for: url, settings: settings)
            
            // Check if base would overwrite source
            let wouldOverwriteSource = (base.standardizedFileURL == url.standardizedFileURL)
            let hasOverlays = settings.burnInFrames || settings.burnInTimecode || settings.burnInFilename
            
            let alloc: OutputAllocation
            if wouldOverwriteSource && !hasOverlays {
                // Force auto-rename: no overlays means no pixel changes, so overwriting source is dangerous
                let dir = base.deletingLastPathComponent()
                let ext = base.pathExtension
                let stem = base.deletingPathExtension().lastPathComponent
                let forcedBase = dir
                    .appendingPathComponent("\(stem)_RENAMED")
                    .appendingPathExtension(ext)
                
                alloc = allocatePlannedOutputURL(base: forcedBase, excludingID: nil)
            } else if wouldOverwriteSource && hasOverlays {
                // Overlays active: warn user but allow (they're creating a modified render)
                alloc = OutputAllocation(
                    url: base,
                    didChange: false,
                    warningReason: "Output will replace source file. Click destination filename to rename."
                )
            } else {
                // Normal case: collision check only
                alloc = allocatePlannedOutputURL(base: base, excludingID: nil)
            }
            
            item.plannedOutputURL = alloc.url
            item.allowOverwrite = false
            item.warningReason = alloc.warningReason

            files.append(item)
        }

        // Second pass: Start per-item background inspection for the *newly appended* rows.
        // (Important: cannot key by URL because duplicates are allowed.)
        let newlyAddedIDs = files.suffix(newUrls.count).map { $0.id }

        for id in newlyAddedIDs {
            Task { @MainActor in
                self.startInspection(for: id)
            }
        }

        // Revalidate immediately after initial add (blocked status, etc.)
        // Metadata-driven validation will refresh again as inspections complete.
        self.revalidateFilesForCurrentMode()
    }
    
    // MARK: - Queue Import (stateful append)

    @MainActor
    func appendImportedQueueItems(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }

        // Append items while preserving their saved queue-row state.
        // Still run admission-time destination allocation so the row has a planned output,
        // and so queue collision logic behaves consistently.
        for var item in items {
            let base = OutputNamer.suggestedOutputURL(for: item.url, settings: settings)
            let alloc = allocatePlannedOutputURL(base: base, excludingID: nil)

            item.plannedOutputURL = alloc.url
            item.allowOverwrite = false

            // Preserve any existing warningReason if you ever persist it later;
            // otherwise use allocator warning.
            if item.warningReason == nil {
                item.warningReason = alloc.warningReason
            }

            files.append(item)
        }

        // Kick off background inspection only for items that are not blocked
        // (blocked missing sources would waste work and/or spam errors).
        let appended = files.suffix(items.count)
        let idsToInspect = appended.filter { $0.status != .blocked }.map { $0.id }

        for id in idsToInspect {
            Task { @MainActor in
                self.startInspection(for: id)
            }
        }

        // Revalidate after importing (farm path checks, etc.)
        revalidateFilesForCurrentMode()
    }
    
    
    // MARK: - Naming-affecting settings changes

    enum NamingChangeReason {
        case suffixChanged
        // future: prefixChanged, containerChanged, scaleChanged, etc.
    }

    /// Single canonical entry point for propagating naming-affecting Settings changes
    /// into the queue's planned outputs + display caches.
    @MainActor
    func applyNamingChangeToQueue(reason: NamingChangeReason) {
        replanPlannedOutputURLsForQueue()
        rebuildCachedDstLinesForQueue()
    }
    
    
    // MARK: - Output planning (canonical)

    // Always route through allocatePlannedOutputURL(base:excludingID:) so policy stays centralized.
    @MainActor
    private func allocatePlannedOutput(forIndex idx: Int) -> OutputAllocation {
        let inputURL = files[idx].url
        let base = OutputNamer.suggestedOutputURL(for: inputURL, settings: settings)
        return allocatePlannedOutputURL(base: base, excludingID: files[idx].id)
    }

    
    
    // MARK: - Queue naming recompute helpers

    @MainActor
    private func replanPlannedOutputURLsForQueue() {
        for idx in files.indices {
            let alloc = allocatePlannedOutput(forIndex: idx)

            files[idx].plannedOutputURL = alloc.url
            files[idx].allowOverwrite = false

            // Keep warningReason consistent with admission-time behavior.
            // If you later add "user-overridden destination", gate this assignment behind a flag.
            files[idx].warningReason = alloc.warningReason
        }
    }


    private func rebuildCachedDstLinesForQueue() {
        for idx in files.indices {
            // Step A (done): you added clearCachedDstLine() on MediaItem
            files[idx].clearCachedDstLine()

            let dstLine = fileService.buildCachedDstLine(
                for: files[idx],
                settings: settings,
                runMode: settings.runMode
            )
            files[idx].setCachedDstLine(dstLine)
        }
    }



    // MARK: - Planned Output Allocation (canonical)

    // Returned by the allocator so admission-time code can persist warnings.
    private struct OutputAllocation {
        let url: URL
        let didChange: Bool
        let warningReason: String?
    }

    @MainActor
    private func allocatePlannedOutputURL(
        base: URL,
        excludingID: MediaItem.ID? = nil
    ) -> OutputAllocation {

        let fm = FileManager.default

        // Reserve: other jobs' planned outputs (case-insensitive, standardized).
        // Policy per spec: only plannedOutputURL participates in queue collision checks.
        var reserved = Set<String>()
        reserved.reserveCapacity(files.count)

        for other in files {
            if let excludingID, other.id == excludingID { continue }
            guard let dst = other.plannedOutputURL else { continue }
            reserved.insert(dst.standardizedFileURL.path.lowercased())
        }

        func isTaken(_ url: URL) -> Bool {
            let key = url.standardizedFileURL.path.lowercased()
            return fm.fileExists(atPath: url.path) || reserved.contains(key)
        }

        // Fast path
        if !isTaken(base) {
            return OutputAllocation(url: base, didChange: false, warningReason: nil)
        }

        // Suffix loop: name.ext -> name_1.ext -> name_2.ext ...
        let dir = base.deletingLastPathComponent()
        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent

        // If stem already ends with _N, strip it and start from N+1
        let regex = try? NSRegularExpression(pattern: #"^(.*)_(\d+)$"#)
        var root = stem
        var startN = 1

        if let regex,
           let m = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
           m.numberOfRanges == 3,
           let r1 = Range(m.range(at: 1), in: stem),
           let r2 = Range(m.range(at: 2), in: stem),
           let n = Int(stem[r2]) {
            root = String(stem[r1])
            startN = max(1, n + 1)
        }

        var n = startN
        while true {
            let name = ext.isEmpty ? "\(root)_\(n)" : "\(root)_\(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)

            if !isTaken(candidate) {
                return OutputAllocation(
                    url: candidate,
                    didChange: true,
                    warningReason: "Output path was automatically renamed to “\(candidate.lastPathComponent)” to avoid overwrite."
                )
            }
            n += 1
        }
    }
    

    // MARK: - Destination Planning (UI-safe)

    @MainActor
    func planOutputURL(base: URL, excludingID: MediaItem.ID? = nil) -> (url: URL, warningReason: String?) {
        let alloc = allocatePlannedOutputURL(base: base, excludingID: excludingID)
        return (alloc.url, alloc.warningReason)
    }

    
    
    
    @MainActor
    func requeueItem(_ id: UUID) {
        guard let idx = files.firstIndex(where: { $0.id == id }) else { return }

        updateFile(at: idx) { file in
            file.isChecked = true
            file.status = .queued
            file.statusReason = nil
            file.progress = nil
            file.etaSeconds = nil
            file.progressMode = .none
            let alloc = resolvedPlannedOutputURLForRequeue(item: file)
            file.plannedOutputURL = alloc.url
            file.warningReason = alloc.warningReason
        }
    }
    
    
    @MainActor
    private func resolvedPlannedOutputURLForRequeue(item: MediaItem) -> OutputAllocation {
        // Prefer the job’s existing plan; fallback to suggested.
        let base = item.plannedOutputURL
            ?? OutputNamer.suggestedOutputURL(for: item.url, settings: settings)

        return allocatePlannedOutputURL(base: base, excludingID: item.id)
    }

    
    
    @MainActor
    func duplicateItems(withIDs ids: Set<MediaItem.ID>) {
        guard !ids.isEmpty else { return }

        // Duplicate in queue order (top -> bottom) and insert each copy immediately after its source.
        let orderedIndices = files.enumerated()
            .filter { ids.contains($0.element.id) }
            .map { $0.offset }
            .sorted()

        guard !orderedIndices.isEmpty else { return }

        var insertOffset = 0

        for originalIndex in orderedIndices {
            let idx = originalIndex + insertOffset
            guard files.indices.contains(idx) else { continue }

            let original = files[idx]

            var dup = MediaItem(url: original.url, meta: original.meta, status: .queued, statusReason: nil)
            dup.isChecked = true

            // Reset attempt-specific fields
            dup.status = .queued
            dup.statusReason = nil
            dup.finalOutputURL = nil
            dup.actualEncodeSeconds = nil
            dup.tempOutputURL = nil
            dup.progressMode = .none
            dup.progress = nil
            dup.etaSeconds = nil
            dup.outputSizeBytes = nil
            dup.logURL = nil
            dup.isProcessingMetadata = false
            dup.metadataProgress = nil

            // Preserve cached display strings if present (optional but nice)
            if let src = original.cachedSrcLine { dup.setCachedSrcLine(src) }
            if let dst = original.cachedDstLine { dup.setCachedDstLine(dst) }
            if let sz  = original.cachedFileSize { dup.setCachedFileSize(sz) }

            let base = original.plannedOutputURL
                ?? OutputNamer.suggestedOutputURL(for: original.url, settings: settings)

            let alloc = allocatePlannedOutputURL(base: base, excludingID: nil)
            dup.plannedOutputURL = alloc.url
            dup.allowOverwrite = false
            dup.warningReason = alloc.warningReason

            files.insert(dup, at: idx + 1)
            insertOffset += 1

            // Kick off background inspection for the duplicate (cheap + keeps pipeline consistent)
            Task { @MainActor in
                self.startInspection(for: dup.id)
            }
        }

        // Revalidate statuses (farm path checks, etc.)
        revalidateFilesForCurrentMode()
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
    
    @MainActor
    func submit(items: [MediaItem]) {
        precondition(Thread.isMainThread, "AppCore.submit(items:) must be called on the main thread")
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
        
        // --------------------------------------------------
        // PREFLIGHT (v1): source exists + destination available
        // --------------------------------------------------
        let selectedIDs = Set(items.map { $0.id })
        let issues = PreflightService.shared.preflightSelected(
            files: &files,
            selectedIDs: selectedIDs,
            settings: settings
        )

        // Emit UI messages for any blocks found during preflight
        for issue in issues {
            let filename = files.first(where: { $0.id == issue.id })?.url.lastPathComponent
            pushMessage(
                level: .error,
                issue.message,
                filename: filename,
                code: .other,
                originKey: "preflight",
                detail: issue.detail ?? issue.sourceURL?.path ?? issue.destinationURL?.path
            )
        }


        // New batch run (one-shot chime resets here)
        didSubmitBatchEncode = true
        didPlayBatchDoneChime = false

        // Normalize selected items:
        // - done/error -> queued (in place)
        // - force-check selection only for queued items
        // - DO NOT auto-requeue blocked items (preflight owns blocked=>unchecked)
        for item in items {
            guard let idx = files.firstIndex(where: { $0.id == item.id }) else { continue }

            switch files[idx].status {
            case .done, .error:
                updateFile(at: idx) { file in
                    file.status = .queued
                    file.statusReason = nil
                    file.isChecked = true

                    // Safety: do NOT carry overwrite intent across attempts unless user re-confirms.
                    file.allowOverwrite = false

                    // Clear attempt UI/progress
                    file.progressMode = .none
                    file.progress = nil
                    file.etaSeconds = nil
                    file.actualEncodeSeconds = nil
                    file.tempOutputURL = nil
                }

            case .queued:
                updateFile(at: idx) { file in
                    file.isChecked = true
                }

            case .blocked, .encoding:
                break
            }
        }


        // Runnable jobs (queued + checked) in queue order
        var runnable = files.filter { $0.status == .queued && $0.isChecked }
        guard !runnable.isEmpty else { return }

        func resolvedDestination(for item: MediaItem) -> URL {
            // Planned is authoritative for NEXT attempt.
            // finalOutputURL is only a legacy fallback (older builds used it for rename).
            item.plannedOutputURL
                ?? item.finalOutputURL
                ?? OutputNamer.suggestedOutputURL(for: item.url, settings: settings)
        }

        let fm = FileManager.default
        var firstClaimForPath: [String: UUID] = [:] // normalizedPath -> winnerID

        for candidate in runnable {
            let dst = resolvedDestination(for: candidate).standardizedFileURL
            let key = dst.path.lowercased()

            // --------------------------------------------------
            // DISK OVERWRITE CHECK
            // --------------------------------------------------
            if fm.fileExists(atPath: dst.path), candidate.allowOverwrite == false {
                if let loserIdx = files.firstIndex(where: { $0.id == candidate.id }) {
                    updateFile(at: loserIdx) { file in
                        file.status = .blocked
                        file.statusReason =
                            "Destination exists: “\(dst.lastPathComponent)”. Rename destination, Unqueue, or Remove."
                        file.isChecked = false
                    }
                }
                continue
            }

            // --------------------------------------------------
            // QUEUE-TO-QUEUE COLLISION CHECK
            // --------------------------------------------------
            if let winnerID = firstClaimForPath[key], winnerID != candidate.id {
                if let loserIdx = files.firstIndex(where: { $0.id == candidate.id }) {
                    let winnerName: String = {
                        if let winItem = files.first(where: { $0.id == winnerID }) {
                            return resolvedDestination(for: winItem).lastPathComponent
                        }
                        return dst.lastPathComponent
                    }()

                    updateFile(at: loserIdx) { file in
                        file.status = .blocked
                        file.statusReason =
                            "Output conflict: would overwrite “\(winnerName)”. Rename destination, Unqueue, or Remove."
                        file.isChecked = false
                    }
                }
            } else {
                firstClaimForPath[key] = candidate.id
            }
        }

        // Rebuild runnable after blocking
        runnable = files.filter { $0.status == .queued && $0.isChecked }
        guard !runnable.isEmpty else { return }

        // Submit to encoding service
        encodingService.submitItems(runnable, settings: settings) { [weak self] itemID, status, reason in
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
        Task { @MainActor in
            self.checkBatchDoneChime()
            self.checkDropletExit()
        }
    }

    func markError(itemID: UUID, reason: String?) {
        updateFile(id: itemID) { file in
            file.status = .error
            file.statusReason = reason
        }
        Task { @MainActor in
            self.checkBatchDoneChime()
            self.checkDropletExit()
        }
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

        checkBatchDoneChime()
        checkDropletExit()
    }


    @MainActor
    private func updateItemStatus(itemID: UUID, status: EncodeStatus, reason: String?) {
        updateFile(id: itemID) { file in
            file.status = status
            file.statusReason = reason
        }

        if status == .done || status == .error {
            checkBatchDoneChime()
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
        panel.nameFieldStringValue = "\(name).mrencode"
        panel.allowedFileTypes = ["mrencode"]
        
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
    
    @MainActor
    func setIngestGroupID(_ ingestGroupID: String, forMediaIDs ids: Set<UUID>) {
        for i in files.indices {
            if ids.contains(files[i].id) {
                files[i].ingestGroupID = ingestGroupID
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
    
    @MainActor
    private func checkBatchDoneChime() {
        NSLog("MrEncode checkBatchDoneChime: entered didSubmit=\(didSubmitBatchEncode) didPlay=\(didPlayBatchDoneChime) files=\(files.count)")

        guard didSubmitBatchEncode, !didPlayBatchDoneChime else { return }
        guard !files.isEmpty else { return }

        let active = files.filter { $0.status == .encoding }
        let queuedChecked = files.filter { $0.status == .queued && $0.isChecked }

        NSLog("MrEncode checkBatchDoneChime: active=\(active.count) queuedChecked=\(queuedChecked.count)")

        let hasActiveOrQueued = !active.isEmpty || !queuedChecked.isEmpty
        guard !hasActiveOrQueued else { return }

        NSLog("MrEncode checkBatchDoneChime: TRIGGERING CHIME")

        didPlayBatchDoneChime = true
        didSubmitBatchEncode = false

        // IMPORTANT: synchronous on MainActor (no Task scheduling race)
        SoundManager.shared.playDoneChime()

        // Let droplet-exit logic decide whether/when to terminate.
        checkDropletExit()
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
            ? (EncodeRenderfarm.detectDeadlineCommand()
               ?? "/Applications/Thinkbox/Deadline10/Resources/deadlinecommand")
            : settings.deadlineCommandPath

        print("🔍 Using Deadline command path: \(dlCmd)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try EncodeRenderfarm.fetchLists(
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

