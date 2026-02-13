//
//  AppState.swift
//

import Foundation
import SwiftUI
import Combine

final class AppState: ObservableObject {

    // Allow non-UI helpers (like EncodeLocal/EncodeRemote) to update file statuses.
    static weak var shared: AppState?

    // MARK: - Published UI state
    @Published var files: [MediaItem] = []

    private let prefs = PreferencesStore()
    @Published var settings: Settings {
        didSet {
            do { try prefs.save(settings) }
            catch { print("⚠️ Preferences save failed: \(error)") }
        }
    }

    // Deadline reachability / lists
    @Published var deadlineAvailable: Bool = false
    @Published var isRefreshingDeadline: Bool = false
    @Published var deadlineError: String?
    @Published var didBootstrapDeadline: Bool = false
    
    // Track multi-selection from the Queue list
    @Published var selectedIDs: Set<MediaItem.ID> = []
    
    // Preferences panel
    @Published var showPreferences: Bool = false
    
    // MARK: - Preset Support (NEW)
    @Published var availablePresets: [EncodingPreset] = []
    @Published var isDropletMode: Bool = false
    private var dropletExitWhenDone: Bool = false

    // MARK: - Process Management for Cancellation
    private static var activeProcesses: [UUID: Process] = [:]
    private static var processQueue = DispatchQueue(label: "mrhevc.processes", attributes: .concurrent)

    // Helper: selected items or all files if nothing selected
    func selectedItemsOrAll() -> [MediaItem] {
        selectedIDs.isEmpty ? files : files.filter { selectedIDs.contains($0.id) }
    }

    // MARK: - Init
    init() {
        do {
            self.settings = try prefs.load()
            self.settings.coerceDropdownDefaultsTopFirst()   // ensure valid top defaults
        } catch {
            self.settings = Settings()
            self.settings.coerceDropdownDefaultsTopFirst()   // also ensure when using defaults
            print("⚠️ Preferences load failed, using defaults: \(error)")
        }
        AppState.shared = self
        
        // Load presets (NEW)
        loadPresets()
    }
    
    // MARK: - Preset Management (NEW)
    
    func loadPresets() {
        availablePresets = PresetManager.shared.loadPresets()
        
        // Ensure selected preset exists, fallback to Default
        if !availablePresets.contains(where: { $0.name == settings.selectedPresetName }) {
            settings.selectedPresetName = "Default"
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
        loadPresets() // Refresh list
        settings.selectedPresetName = name
        
        pushMessage(level: .info, "Saved preset '\(name)'")
    }
    
    func deletePreset(name: String) throws {
        // Don't allow deleting Default preset
        guard name != "Default" else {
            throw PresetError.invalidName("Cannot delete Default preset")
        }
        
        try PresetManager.shared.deletePreset(name: name)
        loadPresets() // Refresh list
        
        // If we deleted the currently selected preset, switch to Default
        if settings.selectedPresetName == name {
            settings.selectedPresetName = "Default"
            applyPreset(name: "Default")
        }
        
        pushMessage(level: .info, "Deleted preset '\(name)'")
    }
    
    func exportDroplet(name: String) {
        PresetManager.shared.showDropletExportDialog(presetName: name, settings: settings) { success in
            DispatchQueue.main.async {
                if success {
                    self.pushMessage(level: .info, "Exported droplet '\(name)'")
                }
            }
        }
    }
    
    // MARK: - Droplet Mode (NEW)
    
    func enterDropletMode(with dropletFile: DropletFile) {
        isDropletMode = true
        dropletExitWhenDone = true
        
        // Apply droplet settings (force auto-encode on)
        var dropletSettings = dropletFile.settings
        dropletSettings.autoEncodeOnDrop = true
        settings.applyPreset(dropletSettings, presetName: "Droplet: \(dropletFile.presetName)")
        
        revalidateFilesForCurrentMode()
        
        pushMessage(level: .info, "Droplet mode: \(dropletFile.presetName)")
    }
    
    private func checkDropletExit() {
        guard isDropletMode && dropletExitWhenDone else { return }
        
        // Check if all encoding is complete
        let hasActiveEncoding = files.contains { $0.status == .encoding }
        let hasQueuedItems = files.contains { $0.status == .queued && $0.isChecked }
        
        if !hasActiveEncoding && !hasQueuedItems && !files.isEmpty {
            // All processing complete - exit after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Process Management
    
    static func registerProcess(_ process: Process, for itemID: UUID) {
        processQueue.async(flags: .barrier) {
            activeProcesses[itemID] = process
        }
    }
    
    static func unregisterProcess(for itemID: UUID) {
        processQueue.async(flags: .barrier) {
            activeProcesses.removeValue(forKey: itemID)
        }
    }
    
    static func cancelProcess(for itemID: UUID) {
        processQueue.sync {
            if let process = activeProcesses[itemID] {
                process.terminate()
                activeProcesses.removeValue(forKey: itemID)
            }
        }
    }
    
    // MARK: - User-facing cancellation
    
    @MainActor
    func cancelEncoding(itemID: UUID) {
        // Update UI immediately
        if let idx = files.firstIndex(where: { $0.id == itemID }) {
            files[idx].status = .queued
            files[idx].statusReason = "Cancelled"
            files[idx].progress = nil
            files[idx].etaSeconds = nil
            files[idx].progressMode = .none
        }
        
        // Cancel the actual process
        Self.cancelProcess(for: itemID)
        
        pushMessage(level: .info,
                   "Encoding cancelled",
                   filename: files.first(where: { $0.id == itemID })?.url.lastPathComponent)
    }
    
    @MainActor
    func cancelAllEncoding() {
        let encodingItems = files.filter { $0.status == .encoding }
        
        for item in encodingItems {
            if let idx = files.firstIndex(where: { $0.id == item.id }) {
                files[idx].status = .queued
                files[idx].statusReason = "Cancelled"
                files[idx].progress = nil
                files[idx].etaSeconds = nil
                files[idx].progressMode = .none
            }
            
            Self.cancelProcess(for: item.id)
        }
        
        if !encodingItems.isEmpty {
            pushMessage(level: .info, "All encoding cancelled")
        }
    }

    // MARK: - File handling
    func addFiles(_ urls: [URL]) {
        // First pass: Add items immediately with minimal blocking work
        let startIndex = files.count
        
        for url in urls {
            var item = MediaItem(
                url: url,
                meta: .empty,
                status: .queued,
                statusReason: nil
            )

            // Only do the minimal synchronous checks needed for UI
            if settings.runMode == .remoteDeadline {
                let check = EncodeRemote.isInputPathAcceptableForFarm(url)
                if !check.ok {
                    item.status = EncodeStatus.blocked
                    item.statusReason = check.reason ?? "Not accessible to render farm."
                    item.isChecked = false
                    pushMessage(level: .warning,
                                "Blocked: \(url.lastPathComponent) — \(check.reason ?? "")",
                                filename: url.lastPathComponent,
                                code: .farmPath,
                                originKey: "farm-path")
                }
            }

            // Auto-check non-blocked items
            item.isChecked = (item.status != EncodeStatus.blocked)
            files.append(item)
        }

        // Update progress tracking for background processing
        backgroundProcessingTotal += urls.count
        backgroundProcessingCount += urls.count

        // Second pass: Immediate lightweight processing, then deferred heavy work
        for (index, url) in urls.enumerated() {
            let itemIndex = startIndex + index
            
            DispatchQueue.global(qos: .utility).async {
                // Quick file size only - no expensive operations
                let fileSize = self.getFileSize(url)
                
                DispatchQueue.main.async {
                    guard self.files.indices.contains(itemIndex),
                          self.files[itemIndex].url == url else { return }
                    
                    // Show as processing with placeholders
                    self.files[itemIndex].isProcessingMetadata = true
                    self.files[itemIndex].setCachedSrcLine("Processing...")
                    self.files[itemIndex].setCachedDstLine("Estimating...")
                    if let size = fileSize {
                        self.files[itemIndex].setCachedFileSize(size)
                    }
                }
                
                // Stagger the expensive operations to avoid overwhelming the system
                let delay = Double(index) * 0.3  // 300ms between each file
                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + delay) {
                    self.processMetadataDeferred(url: url, itemIndex: itemIndex, fileSize: fileSize)
                }
            }
        }
    }

    private func processMetadataDeferred(url: URL, itemIndex: Int, fileSize: Int64?) {
        // This runs on background thread, staggered to avoid VPN/ExifTool overload
        let meta = MetadataExtractor.extract(for: url)  // ExifTool runs here, one at a time
        let srcLine = buildCachedSrcLine(url: url, meta: meta, fileSize: fileSize)
        let dstLine = buildCachedDstLine(url: url, meta: meta)
        
        DispatchQueue.main.async {
            // Update with real metadata
            if let idx = self.files.firstIndex(where: { $0.url == url }) {
                self.files[idx].meta = meta
                self.files[idx].setCachedSrcLine(srcLine)
                self.files[idx].setCachedDstLine(dstLine)
                self.files[idx].isProcessingMetadata = false
                self.validateItemSettings(at: idx)
            }
            
            // Update progress tracking
            self.backgroundProcessingCount = max(0, self.backgroundProcessingCount - 1)
        }
    }
    
    // HELPER METHODS:
    private func getFileSize(_ url: URL) -> Int64? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return attrs[.size] as? Int64
        } catch {
            return nil
        }
    }

    private func buildCachedSrcLine(url: URL, meta: MediaMetadata, fileSize: Int64?) -> String {
        var parts: [String] = []
        
        // Use metadata when available, avoid creating AVAsset
        if let fps = meta.nominalFPS, fps > 0 {
            let fpsInt = Int(round(fps))
            parts.append("\(fpsInt) fps")
        }
        
        let dur = meta.durationSeconds
        if dur > 0 {
            let mins = Int(dur) / 60
            let secs = Int(dur) % 60
            parts.append(String(format: "%d:%02d", mins, secs))
        }
        
        // Add NCLC info if available from metadata
        if let p = meta.colorPrimaries, let t = meta.transferFunction, let m = meta.ycbcrMatrix,
           !p.isEmpty, !t.isEmpty, !m.isEmpty {
            // Build consolidated NCLC display similar to nclcDisplayNow
            if let pInt = Int(p), let tInt = Int(t), let mInt = Int(m) {
                if let label = consolidatedNCLCLabel(for: pInt, tInt, mInt) {
                    parts.append("\(label) [\(p), \(t), \(m)]")
                } else {
                    parts.append("NCLC [\(p), \(t), \(m)]")
                }
            }
        }
        
        if let size = fileSize {
            let mb = Double(size) / 1_000_000.0
            if mb >= 1000 { parts.append(String(format: "%.1f GB", mb / 1000.0)) }
            else { parts.append(String(format: "%.1f MB", mb)) }
        }
        
        return parts.joined(separator: " • ")
    }

    // Add this helper function to AppState.swift
    private func consolidatedNCLCLabel(for p: Int, _ t: Int, _ m: Int) -> String? {
        switch (p, t, m) {
        case (1, 1, 1):   return "Rec.709"
        case (1, 13, 1):  return "Rec.709 (sRGB TF)"
        case (12, 1, 1):  return "Display P3"
        case (12, 13, 1): return "Display P3 (sRGB TF)"
        case (9, 16, 9):  return "BT.2020 PQ (HDR10)"
        case (9, 18, 9):  return "BT.2020 HLG"
        case (9, 1, 9):   return "BT.2020 (709 TF)"
        case (6, 1, 6):   return "BT.601 NTSC"
        case (5, 1, 5):   return "BT.601 PAL"
        default:          return nil
        }
    }

    private func buildCachedDstLine(url: URL, meta: MediaMetadata) -> String {
        // Generate proper estimates with correct wording
        let estWallTime: Double? = EncodeTimeEstimator.estimateSeconds(
            url: url,
            meta: meta,
            settings: settings,
            runMode: settings.runMode
        )
        
        var parts: [String] = []
        
        // Add size estimate using simple formatting
        if let est = OutputEstimator.estimate(url: url, meta: meta, settings: settings) {
            let mb = est.estBytes / 1_000_000.0
            if mb >= 1000 {
                parts.append("\(String(format: "%.1f GB", mb / 1000.0))")
            } else {
                parts.append("\(String(format: "%.1f MB", mb))")
            }
        }
        
        // Add time estimate
        if let wallTime = estWallTime, wallTime.isFinite, wallTime > 0 {
            parts.append("Est. Render Time: \(EncodeTimeEstimator.formatTime(wallTime))")
        }
        
        return parts.isEmpty ? "Estimating..." : parts.joined(separator: " • ")
    }

    private func validateItemSettings(at index: Int) {
        guard files.indices.contains(index) else { return }
        var item = files[index]
        
        if item.status == EncodeStatus.blocked { return } // Skip already blocked items
        
        // Existing validation logic...
        let compressionInactive = settings.bypassHEVC &&
                                 settings.scale == .oneToOne &&
                                 settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        let nclcInactive = settings.nclcTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no change" &&
                          settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        let overlaysInactive = !(settings.burnInFrames || settings.burnInTimecode || settings.burnInFilename)
        
        if compressionInactive && nclcInactive && overlaysInactive {
            item.status = EncodeStatus.blocked
            item.statusReason = "Nothing to do!"
            item.isChecked = false
            pushMessage(level: .warning,
                        "Nothing to do: \(item.url.lastPathComponent) — no changes selected.",
                        filename: item.url.lastPathComponent,
                        code: .noOp,
                        originKey: "preflight-noop")
        } else {
            let allSuffixesBlank = settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                   settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                                   settings.scaleSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
            if allSuffixesBlank {
                let reason = "Output name would match source. Add a suffix."
                item.status = EncodeStatus.blocked
                item.statusReason = reason
                item.isChecked = false
                pushMessage(level: .error,
                            "Would overwrite: \(item.url.lastPathComponent) — \(reason)",
                            filename: item.url.lastPathComponent,
                            code: .wouldOverwrite,
                            originKey: "preflight-overwrite")
            }
            
            // POOL VALIDATION:
            else if settings.runMode == .remoteDeadline {
                let poolCheck = settings.pool.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let groupCheck = settings.group.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                
                if poolCheck.isEmpty || poolCheck == "none" {
                    let reason = "Deadline pool is 'none' - jobs will not start."
                    item.status = EncodeStatus.blocked
                    item.statusReason = reason
                    item.isChecked = false
                    pushMessage(level: .error,
                                "Blocked: \(item.url.lastPathComponent) — \(reason)",
                                filename: item.url.lastPathComponent,
                                code: .other,
                                originKey: "deadline-pool")
                } else if groupCheck.isEmpty || groupCheck == "none" {
                    let reason = "Deadline group is 'none' - jobs will not start."
                    item.status = EncodeStatus.blocked
                    item.statusReason = reason
                    item.isChecked = false
                    pushMessage(level: .error,
                                "Blocked: \(item.url.lastPathComponent) — \(reason)",
                                filename: item.url.lastPathComponent,
                                code: .other,
                                originKey: "deadline-group")
                }
            }
        }
        
        files[index] = item
    }

    // Recompute block/unblock from scratch based on CURRENT settings + path access,
    // and auto-acknowledge latest error messages for categories that are now resolved.
    func revalidateFilesForCurrentMode() {
        var anyFarmBlockedNow = false
        var anyNoOpBlockedNow = false
        var anyOverwriteBlockedNow = false
        var anyPoolBlockedNow = false  // ADD THIS

        for i in files.indices {
            var item = files[i]

            // Leave active/finished rows alone
            switch item.status {
            case .encoding, .done:
                continue
            default:
                break
            }

            // 1) Remote path gating (only matters in Remote mode)
            var newReason: String? = nil
            var newCat: LogCode? = nil

            if settings.runMode == .remoteDeadline {
                let okFarm = EncodeRemote.isInputPathAcceptableForFarm(item.url)
                if !okFarm.ok {
                    newReason = okFarm.reason ?? "Not accessible to render farm."
                    newCat = .farmPath
                    anyFarmBlockedNow = true
                }
                
                // ADD POOL CHECK HERE:
                else {
                    let poolCheck = settings.pool.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if poolCheck.isEmpty || poolCheck == "none" {
                        newReason = "Deadline pool is 'none' - jobs will not start."
                        newCat = .other
                        anyPoolBlockedNow = true
                    }
                }
            }

            // 2) No-op / overwrite gating (applies in both modes)
            if newReason == nil {
                // ... existing compression/nclc/overlays logic ...
            }

            // 3) Apply final status
            if let reason = newReason {
                item.status = .blocked
                item.statusReason = reason
            } else {
                item.status = .queued
                item.statusReason = nil
            }

            files[i] = item
        }

        // 4) Auto-acknowledge message categories that are NOW resolved
        acknowledgeLatestIfResolved(.farmPath, stillPresent: anyFarmBlockedNow)
        acknowledgeLatestIfResolved(.noOp, stillPresent: anyNoOpBlockedNow)
        acknowledgeLatestIfResolved(.wouldOverwrite, stillPresent: anyOverwriteBlockedNow)
        // ADD THIS LINE:
        acknowledgeLatestIfResolved(.other, stillPresent: anyPoolBlockedNow)
    }

    /// Mark the most recent, unacknowledged message of `code` as acknowledged
    /// when that category is no longer present.
    private func acknowledgeLatestIfResolved(_ code: LogCode, stillPresent: Bool) {
        guard !stillPresent else { return }
        if let idx = uiMessages.lastIndex(where: { $0.code == code && $0.acknowledged == false }) {
            uiMessages[idx].acknowledged = true
        }
    }

    func clear() {
        files.removeAll()
    }

    func saveSettings() {
        do { try prefs.save(settings) }
        catch { print("⚠️ Preferences save failed: \(error)") }
    }
    
    /// Blocks "Nothing to do!" and "output would overwrite" cases; unblocks them if settings change.
    private func applyOverwriteSanity(to item: inout MediaItem) {
        // Scenario 1: all panels inactive → nothing to do
        if settings.isEverythingInactive {
            item.status = .blocked
            item.statusReason = "Nothing to do!"
            return
        }

        // Scenario 2: both suffixes blank → output name would match source
        if settings.bothSuffixesBlank {
            item.status = .blocked
            item.statusReason = "Output name would match source. Add a suffix in NCLC Settings or Compression & Resizing."
            return
        }

        // If previously blocked for one of our reasons and now safe, unblock.
        if item.status == .blocked,
           let reason = item.statusReason,
           reason.hasPrefix("Nothing to do!") || reason.hasPrefix("Output name would match source") {
            item.status = .queued
            item.statusReason = nil
        }
    }

    // MARK: - Status helpers
    /// Index-based status setter (used by remote submit loop).
    func setStatus(_ status: EncodeStatus, forIndex index: Int) {
        DispatchQueue.main.async {
            if self.files.indices.contains(index) {
                self.files[index].status = status
                
                // Check for droplet exit after status changes (NEW)
                self.checkDropletExit()
            }
        }
    }

    // MARK: - Row status helpers (single, canonical implementations)
    @MainActor
    func markEncoding(itemID: UUID) {
        if let i = files.firstIndex(where: { $0.id == itemID }) {
            files[i].status = .encoding
            files[i].statusReason = nil
        }
    }

    @MainActor
    func markFinished(itemID: UUID, outputURL: URL) {
        if let i = files.firstIndex(where: { $0.id == itemID }) {
            files[i].finalOutputURL = outputURL     // persist what was actually written
            files[i].status = .done
            files[i].statusReason = nil
        }
        
        // Check for droplet exit after completion (NEW)
        checkDropletExit()
    }

    @MainActor
    func markError(itemID: UUID, reason: String?) {
        if let i = files.firstIndex(where: { $0.id == itemID }) {
            files[i].status = .error
            files[i].statusReason = reason
        }
        
        // Check for droplet exit even on errors (NEW)
        checkDropletExit()
    }

    // MARK: - Submit
    func submit() {
        print("🧰 submit() queued:", files.filter { $0.status == .queued }.count,
              "mode:", settings.runMode.rawValue)
        guard !files.isEmpty else { return }

        switch settings.runMode {
        case .localFFmpeg:
            let itemsSnapshot = files
            let settingsSnapshot = settings
            DispatchQueue.global(qos: .userInitiated).async {
                EncodeLocal.run(items: itemsSnapshot, settings: settingsSnapshot)
            }

        case .remoteDeadline:
            // Resolve deadlinecommand path: user override > detect marker
            let dlCmd = settings.deadlineCommandPath.isEmpty
                ? (EncodeRemote.detectDeadlineCommand()
                   ?? "/Applications/Thinkbox/Deadline10/Resources/deadlinecommand")
                : settings.deadlineCommandPath

            // Path to ffmpeg as seen by farm workers
            let ffmpegOnFarm = "/usr/local/bin/ffmpeg"

            let itemsSnapshot = files
            let settingsSnapshot = settings

            DispatchQueue.global(qos: .userInitiated).async {
                for (idx, item) in itemsSnapshot.enumerated() {
                    if item.status == .blocked { continue }

                    // Indicate "encoding" while we generate & submit
                    self.setStatus(.encoding, forIndex: idx)

                    let result = EncodeRemote.submitFFmpegJob(
                        deadlineCmd: dlCmd,
                        item: item,
                        settings: settingsSnapshot,
                        ffmpegPath: ffmpegOnFarm
                    )

                    if result.exitCode == 0 {
                        self.setStatus(.done, forIndex: idx)
                    } else {
                        self.setStatus(.error, forIndex: idx)
                        DispatchQueue.main.async {
                            self.deadlineError = result.rawOutput
                            print("❌ Submit failed for \(item.url.lastPathComponent):\n\(result.rawOutput)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bootstrap on launch
    func bootstrapDeadlineLists() {
        // Use cached lists immediately (persisted in Settings)
        self.deadlineAvailable = !(settings.poolOptions.isEmpty && settings.groupOptions.isEmpty)
        // Kick a background refresh to get fresh Pools/Groups
        refreshDeadlineOptions(inBackground: true)
    }

    // MARK: - Deadline lists refresh
    func refreshDeadlineOptions(inBackground: Bool = false) {
        if isRefreshingDeadline { return }
        isRefreshingDeadline = true
        deadlineError = nil

        let dlCmd = settings.deadlineCommandPath.isEmpty
            ? (EncodeRemote.detectDeadlineCommand()
               ?? "/Applications/Thinkbox/Deadline10/Resources/deadlinecommand")
            : settings.deadlineCommandPath

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let lists = try EncodeRemote.fetchLists(deadlineCmd: dlCmd)
                DispatchQueue.main.async {
                    self.settings.poolOptions = lists.pools
                    self.settings.groupOptions = lists.groups
                    self.settings.coerceDropdownDefaultsTopFirst()
                    self.settings.lastDeadlineFetch = Date()
                    self.deadlineAvailable = true
                    self.isRefreshingDeadline = false
                }
            } catch {
                DispatchQueue.main.async {
                    let hasCache = !(self.settings.poolOptions.isEmpty && self.settings.groupOptions.isEmpty)
                    self.deadlineAvailable = hasCache
                    self.deadlineError = error.localizedDescription
                    if !inBackground {
                        print("Deadline refresh failed: \(error)")
                    }
                    self.isRefreshingDeadline = false
                }
            }
        }
    }
    
    // MARK: - Messaging Log
    @Published var uiMessages: [AppLogEntry] = []

    /// Push a concise user-facing message (keeps only the last 5)
    func pushMessage(level: LogLevel,
                     _ message: String,
                     filename: String? = nil,
                     code: LogCode? = nil,
                     originKey: String? = nil,
                     detail: String? = nil,
                     jobID: String? = nil,
                     logURL: URL? = nil)
    {
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
        if uiMessages.count > 5 { uiMessages.removeFirst(uiMessages.count - 5) }
    }
    
    // For background processing feedback:
    @Published var backgroundProcessingCount: Int = 0
    @Published var backgroundProcessingTotal: Int = 0
    
    var isBackgroundProcessing: Bool {
        backgroundProcessingCount > 0
    }
    
    var backgroundProgress: Double {
        guard backgroundProcessingTotal > 0 else { return 0.0 }
        let completed = backgroundProcessingTotal - backgroundProcessingCount
        return Double(completed) / Double(backgroundProcessingTotal)
    }

}

// ==============================
// MARK: - Queue actions (selection-aware)
// ==============================
@MainActor
extension AppState {

    /// Encode only specific items. If `items` is empty, do nothing (UI chooses "all" before calling).
    /// Re-queues previously rendered items and overwrites the same output path.
    func submit(items: [MediaItem]) {
        guard !items.isEmpty else { return }

        // Re-queue any finished/blocked/error items so they can run again (overwrite).
        for id in items.map({ $0.id }) {
            if let idx = files.firstIndex(where: { $0.id == id }) {
                switch files[idx].status {
                case .done, .error, .blocked:
                    files[idx].status = .queued
                    files[idx].statusReason = nil
                    // keep finalOutputURL so encoders overwrite same file
                default:
                    break
                }
            }
        }

        // Dispatch to the selected run mode.
        switch settings.runMode {
        case .localFFmpeg:
            EncodeLocal.run(items: items, settings: settings)            // let it auto-discover
        case .remoteDeadline:
            EncodeRemote.run(items: items, settings: settings)
        }
    }

    /// Remove everything that isn't currently encoding.
    func clearAllNonEncoding() {
        files.removeAll { $0.status != .encoding }
    }

    /// Remove specific items (won't remove ones actively encoding).
    @MainActor
    func removeItems(withIDs ids: Set<MediaItem.ID>) {
        files.removeAll { item in
            ids.contains(item.id) && item.status != .encoding
        }
    }
}


// MARK: - Global Progress (computed properties)
extension AppState {
    /// Overall progress across all encoding items (0.0 to 1.0)
    var globalProgress: Double {
        let activeItems = files.filter { $0.status == .encoding }
        guard !activeItems.isEmpty else { return 0.0 }
        
        let progressValues = activeItems.compactMap { $0.progress }
        guard !progressValues.isEmpty else { return 0.0 }
        
        return progressValues.reduce(0.0, +) / Double(progressValues.count)
    }
    
    /// Text description of current encoding status
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
}
