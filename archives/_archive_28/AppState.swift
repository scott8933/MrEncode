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
    }

    // MARK: - File handling
    func addFiles(_ urls: [URL]) {
        for url in urls {
            var item = MediaItem(
                url: url,
                meta: .empty,
                status: .queued,
                statusReason: nil
            )

            // Remote sanity check
            if settings.runMode == .remoteDeadline {
                let check = EncodeRemote.isInputPathAcceptableForFarm(url)
                if !check.ok {
                    item.status = .blocked
                    let reason = check.reason ?? "Not accessible to render farm."
                    item.statusReason = reason
                    item.isChecked = false
                    // Message Area: Blocked (remote path)
                    pushMessage(level: .warning,
                                "Blocked: \(url.lastPathComponent) — \(reason)",
                                filename: url.lastPathComponent,
                                code: .farmPath,
                                originKey: "farm-path")
                }
            }

            // Overwrite / no-op sanity (only if not already blocked)
            if item.status != .blocked {
                // Panel inactivity
                let compressionInactive =
                    settings.bypassHEVC &&
                    settings.scale == .oneToOne &&
                    settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                let nclcInactive =
                    settings.nclcTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no change" &&
                    settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                let overlaysInactive = !(settings.burnInFrames || settings.burnInTimecode || settings.burnInFilename)

                // 1) Nothing to do (all panels effectively pass-through)
                if compressionInactive && nclcInactive && overlaysInactive {
                    item.status = .blocked
                    item.statusReason = "Nothing to do!"
                    item.isChecked = false
                    // Message Area: Blocked (no-op)
                    pushMessage(level: .warning,
                                "Nothing to do: \(url.lastPathComponent) — no changes selected.",
                                filename: url.lastPathComponent,
                                code: .noOp,
                                originKey: "preflight-noop")
                } else {
                    // 2) Output name would match source (all suffix panels blank)
                    let allSuffixesBlank =
                        settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                        settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                        settings.scaleSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                    if allSuffixesBlank {
                        let reason = "Output name would match source. Add a suffix in NCLC Settings, Scale & Crop, or Compression."
                        item.status = .blocked
                        item.statusReason = reason
                        item.isChecked = false
                        // Message Area: Blocked (would overwrite)
                        pushMessage(level: .error,
                                    "Would overwrite: \(url.lastPathComponent) — \(reason)",
                                    filename: url.lastPathComponent,
                                    code: .wouldOverwrite,
                                    originKey: "preflight-overwrite")
                    }
                }
            }

            // Auto-check new items that aren’t blocked
            item.isChecked = (item.status != .blocked)

            files.append(item)

            // Async metadata extraction, then patch matching row on main
            let rowIndex = files.count - 1
            DispatchQueue.global(qos: .userInitiated).async {
                let meta = MetadataExtractor.extract(for: url)
                DispatchQueue.main.async {
                    if self.files.indices.contains(rowIndex) && self.files[rowIndex].url == url {
                        self.files[rowIndex].meta = meta
                    }
                }
            }
        }
    }

    // Recompute block/unblock from scratch based on CURRENT settings + path access,
    // and auto-acknowledge latest error messages for categories that are now resolved.
    func revalidateFilesForCurrentMode() {
        var anyFarmBlockedNow = false
        var anyNoOpBlockedNow = false
        var anyOverwriteBlockedNow = false

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
            }

            // 2) No-op / overwrite gating (applies in both modes)
            if newReason == nil {
                let compressionInactive =
                    settings.bypassHEVC &&
                    settings.scale == .oneToOne &&
                    settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let nclcInactive =
                    settings.nclcTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no change" &&
                    settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let overlaysInactive = !(settings.burnInFrames || settings.burnInTimecode || settings.burnInFilename)

                if compressionInactive && nclcInactive && overlaysInactive {
                    newReason = "Nothing to do!"
                    newCat = .noOp
                    anyNoOpBlockedNow = true
                } else {
                    let bothSuffixesBlank =
                        settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                        settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if bothSuffixesBlank {
                        newReason = "Output name would match source. Add a suffix in NCLC Settings or Compression."
                        newCat = .wouldOverwrite
                        anyOverwriteBlockedNow = true
                    }
                }
            }

            // 3) Apply final status
            if let reason = newReason {
                item.status = .blocked
                item.statusReason = reason
                // do not auto-uncheck here; that was handled elsewhere
            } else {
                item.status = .queued
                item.statusReason = nil
            }

            files[i] = item
        }

        // 4) Auto-acknowledge message categories that are NOW resolved (none present)
        acknowledgeLatestIfResolved(.farmPath, stillPresent: anyFarmBlockedNow)
        acknowledgeLatestIfResolved(.noOp, stillPresent: anyNoOpBlockedNow)
        acknowledgeLatestIfResolved(.wouldOverwrite, stillPresent: anyOverwriteBlockedNow)
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
    }

    @MainActor
    func markError(itemID: UUID, reason: String?) {
        if let i = files.firstIndex(where: { $0.id == itemID }) {
            files[i].status = .error
            files[i].statusReason = reason
        }
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

                    // Indicate “encoding” while we generate & submit
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
                            print("✗ Submit failed for \(item.url.lastPathComponent):\n\(result.rawOutput)")
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

    /// Remove specific items (won’t remove ones actively encoding).
    @MainActor
    func removeItems(withIDs ids: Set<MediaItem.ID>) {
        files.removeAll { item in
            ids.contains(item.id) && item.status != .encoding
        }
    }
}
