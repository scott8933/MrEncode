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
    @Published var settings: Settings = .init()
    @Published var prefs = PreferencesStore()
    @Published var isEncoding: Bool = false

    // Deadline reachability / lists
    @Published var deadlineAvailable: Bool = false
    @Published var isRefreshingDeadline: Bool = false
    @Published var deadlineError: String?
    @Published var didBootstrapDeadline: Bool = false

    // Track multi-selection from the Queue list
    @Published var selectedIDs: Set<MediaItem.ID> = []

    // MARK: - Compact App Log (concise UI log at bottom)
    @Published var logs: [AppLogEntry] = []
    @Published var showLogPane: Bool = false
    private let logLimit = 200

    func log(_ level: LogLevel, _ message: String, fileURL: URL? = nil, autoReveal: Bool = false) {
        let entry = AppLogEntry(date: Date(),
                                level: level,
                                message: message,
                                filename: fileURL?.lastPathComponent)
        logs.append(entry)
        if logs.count > logLimit {
            logs.removeFirst(logs.count - logLimit)
        }
        if autoReveal && level != .info {
            showLogPane = true
        }
        #if DEBUG
        let name = fileURL?.lastPathComponent ?? "-"
        print("[\(level.rawValue.uppercased())] \(name): \(message)")
        #endif
    }

    func clearLogs() { logs.removeAll() }

    // Helper: selected items or all files if nothing selected
    func selectedItemsOrAll() -> [MediaItem] {
        selectedIDs.isEmpty ? files : files.filter { selectedIDs.contains($0.id) }
    }

    // MARK: - Actions

    /// Submit a specific list (used by ContentView action bar).
    func submit(items: [MediaItem]) {
        guard !items.isEmpty else { return }
        switch settings.runMode {
        case .localFFmpeg:
            // Let EncodeLocal resolve ffmpeg path.
            EncodeLocal.run(items: items, settings: settings, ffmpegPath: nil)
        case .remoteDeadline:
            EncodeRemote.run(items: items, settings: settings)
        }
    }

    /// Back-compat: encode/submit all currently queued items (used by UI_Queue auto-encode-on-drop).
    func submit() {
        let queued = files.filter { $0.status == MediaStatus.queued }
        submit(items: queued)
    }

    /// Remove everything that isn't currently encoding.
    func clearAllNonEncoding() {
        files.removeAll { $0.status != MediaStatus.encoding }
    }

    /// Remove specific items (won’t remove ones actively encoding).
    @MainActor
    func removeItems(withIDs ids: Set<MediaItem.ID>) {
        files.removeAll { item in
            ids.contains(item.id) && item.status != MediaStatus.encoding
        }
    }

    // MARK: - File handling

    func addFiles(_ urls: [URL]) {
        for url in urls {
            // Minimal initializer — no .meta in this baseline
            var item = MediaItem(url: url, status: MediaStatus.queued, statusReason: nil)

            // Remote sanity check
            if settings.runMode == .remoteDeadline {
                let check = EncodeRemote.isInputPathAcceptableForFarm(url)
                if !check.ok {
                    item.status = MediaStatus.blocked
                    item.statusReason = check.reason ?? "Not accessible to render farm."
                }
            }

            // Run dimension preflight immediately (warns once per item)
            VideoPreflight.warnIfEvenizeNeeded(for: item, settings: settings)

            files.append(item)

            // (Removed async MetadataExtractor patch — this baseline does not store per-item metadata)
        }
    }

    func revalidateFilesForCurrentMode() {
        for i in files.indices {
            switch settings.runMode {
            case .localFFmpeg:
                if files[i].status == MediaStatus.blocked {
                    files[i].status = MediaStatus.queued
                    files[i].statusReason = nil
                }
            case .remoteDeadline:
                let check = EncodeRemote.isInputPathAcceptableForFarm(files[i].url)
                if !check.ok {
                    files[i].status = MediaStatus.blocked
                    files[i].statusReason = check.reason ?? "Not accessible to render farm."
                } else if files[i].status == MediaStatus.blocked {
                    files[i].status = MediaStatus.queued
                    files[i].statusReason = nil
                }
            }
        }
    }

    /// Re-check all items (de-duped per item id by VideoPreflight).
    func preflightAllVisibleItems() {
        for item in files {
            VideoPreflight.warnIfEvenizeNeeded(for: item, settings: settings)
        }
    }

    // MARK: - Deadline

    /// Refresh Pools/Groups/Path and detect availability
    func refreshDeadlineOptions(inBackground: Bool = false) {
        if isRefreshingDeadline { return }
        isRefreshingDeadline = true
        deadlineError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let detected = EncodeRemote.detectDeadlineCommand()
            var available = (detected != nil)
            var lists: EncodeRemote.Lists = .init(pools: [], groups: [])

            if available {
                do {
                    let cmd = self.settings.deadlineCommandPath.isEmpty ? (detected ?? "") : self.settings.deadlineCommandPath
                    lists = try EncodeRemote.fetchLists(deadlineCmd: cmd)
                } catch {
                    available = false
                    self.deadlineError = error.localizedDescription
                }
            }

            DispatchQueue.main.async {
                self.deadlineAvailable = available
                self.isRefreshingDeadline = false
                if available {
                    // Write into baseline Settings fields
                    self.settings.poolOptions  = lists.pools
                    self.settings.groupOptions = lists.groups

                    // Initialize chosen pool/group if empty
                    if self.settings.pool.isEmpty, let first = lists.pools.first {
                        self.settings.pool = first
                    }
                    if self.settings.group.isEmpty, let first = lists.groups.first {
                        self.settings.group = first
                    }
                }
            }
        }
    }

    func bootstrapDeadlineLists() {
        if didBootstrapDeadline { return }
        didBootstrapDeadline = true
        refreshDeadlineOptions(inBackground: true)
    }

    // MARK: - Encode lifecycle helpers

    @MainActor
    func markQueued(itemID: UUID, reason: String?) {
        if let i = files.firstIndex(where: { $0.id == itemID }) {
            files[i].status = MediaStatus.queued
            files[i].statusReason = reason
        }
    }

    @MainActor
    func markStarted(itemID: UUID) {
        if let i = files.firstIndex(where: { $0.id == itemID }) {
            files[i].status = MediaStatus.encoding
            files[i].statusReason = nil
            files[i].progress = 0
            files[i].etaSeconds = nil
            files[i].progressMode = .none
        }
    }

    @MainActor
    func markProgress(itemID: UUID, progress: Double, etaSeconds: Double?, mode: ProgressMode) {
        if let i = files.firstIndex(where: { $0.id == itemID }) {
            files[i].progress = progress
            files[i].etaSeconds = etaSeconds
            files[i].progressMode = mode
        }
    }

    @MainActor
    func markFinished(itemID: UUID, outputURL: URL) {
        if let i = files.firstIndex(where: { $0.id == itemID }) {
            files[i].finalOutputURL = outputURL     // persist what was actually written
            files[i].status = MediaStatus.done
            files[i].statusReason = nil
        }
    }

    @MainActor
    func markError(itemID: UUID, reason: String?) {
        if let i = files.firstIndex(where: { $0.id == itemID }) {
            files[i].status = MediaStatus.error
            files[i].statusReason = reason
        }
    }

    // MARK: - Init
    init() {
        do {
            self.settings = try prefs.load()
        } catch {
            self.settings = Settings()
            print("⚠️ Preferences load failed, using defaults: \(error)")
        }
        AppState.shared = self
    }
}
