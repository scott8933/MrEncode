// =============================
// File: AppState.swift
// =============================
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
    
    /// Record the actual output path and mark the item finished.
    /// Call this on success from EncodeLocal/EncodeRemote with the SAME output URL passed to ffmpeg/Deadline.
    @MainActor
    func markFinished(itemID: UUID, outputURL: URL) {
        guard let idx = files.firstIndex(where: { $0.id == itemID }) else { return }
        files[idx].finalOutputURL = outputURL
        files[idx].status = .done
        files[idx].statusReason = nil
    }

    /// If you ever re-queue an item, clear the previous finished path so the UI recomputes the suggestion.
    @MainActor
    func resetForRequeue(itemID: UUID) {
        guard let idx = files.firstIndex(where: { $0.id == itemID }) else { return }
        files[idx].finalOutputURL = nil
        files[idx].status = .queued
        files[idx].statusReason = nil
    }



    // MARK: - Init
    init() {
        do {
            self.settings = try prefs.load()
        } catch {
            self.settings = Settings()
            print("⚠️ Preferences load failed, using defaults: \(error)")
        }
        AppState.shared = self   // <-- move this *after* settings is initialized
    }

    // MARK: - File handling
    func addFiles(_ urls: [URL]) {
        for url in urls {
            var item = MediaItem(url: url, status: .queued, statusReason: nil, meta: .empty)

            // Remote sanity check (your existing logic)
            if settings.runMode == .remoteDeadline {
                let check = EncodeRemote.isInputPathAcceptableForFarm(url)
                if !check.ok {
                    item.status = .blocked
                    item.statusReason = check.reason ?? "Not accessible to render farm."
                }
            }

            files.append(item)

            // Kick off metadata extraction in background, then patch row on main
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

    
    func revalidateFilesForCurrentMode() {
        for i in files.indices {
            switch settings.runMode {
            case .localFFmpeg:
                // Local mode: anything can run; clear 'blocked' back to queued
                if files[i].status == .blocked {
                    files[i].status = .queued
                    files[i].statusReason = nil
                }

            case .remoteDeadline:
                // Remote mode: re-check each file
                let check = EncodeRemote.isInputPathAcceptableForFarm(files[i].url)
                if !check.ok {
                    files[i].status = .blocked
                    files[i].statusReason = check.reason ?? "Not accessible to render farm."
                } else if files[i].status == .blocked {
                    files[i].status = .queued
                    files[i].statusReason = nil
                }
            }
        }
    }


    func clear() {
        files.removeAll()
    }

    func saveSettings() {
        do { try prefs.save(settings) }
        catch { print("⚠️ Preferences save failed: \(error)") }
    }

    // MARK: - Status helpers
    func setStatus(_ status: MediaStatus, forIndex index: Int) {
        DispatchQueue.main.async {
            if self.files.indices.contains(index) {
                self.files[index].status = status
            }
        }
    }

    // MARK: - Submit
    func submit() {
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
                    // Skip any files that were blocked at drop
                    if item.status == .blocked {
                        continue
                    }

                    // Show "encoding" while we generate+submit
                    self.setStatus(.encoding, forIndex: idx)

                    var liveItem = item
                    if self.files.indices.contains(idx) {
                        liveItem.meta = self.files[idx].meta     // ← ensure TC/FPS are fresh
                    }
                    let result = EncodeRemote.submitFFmpegJob(
                        deadlineCmd: dlCmd,
                        item: liveItem,
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
}
