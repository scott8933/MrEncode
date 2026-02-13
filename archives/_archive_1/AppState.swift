import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    // Files + settings
    @Published var files: [MediaItem] = []
    @Published var settings: Settings = Settings()

    // Deadline state
    @Published var deadlineAvailable: Bool = false
    @Published var deadlineError: String? = nil
    @Published var isRefreshingDeadline: Bool = false

    private let prefs = PreferencesStore()

    // MARK: Init

    init() {
        if let loaded = try? prefs.load() {
            self.settings = loaded
        }

        // If we already have cached lists, expose them immediately.
        let hasCached = !(settings.poolOptions.isEmpty && settings.groupOptions.isEmpty)
        self.deadlineAvailable = hasCached

        // Make sure we have a command path (best-effort)
        if settings.deadlineCommandPath.isEmpty, let auto = DeadlineService.detectFromMarker() {
            settings.deadlineCommandPath = auto
        }
    }

    func saveSettings() {
        do { try prefs.save(settings) } catch { print("Prefs save error:", error) }
    }

    // MARK: Files

    func addFiles(_ urls: [URL]) {
        let movs = urls.filter { $0.pathExtension.lowercased() == "mov" }
        let existing = Set(files.map { $0.url })
        let newOnes = movs.filter { !existing.contains($0) }
        files.append(contentsOf: newOnes.map { MediaItem(url: $0) })
    }
    func clear() { files.removeAll() }

    // MARK: Deadline lists

    /// Call this on app launch (and optionally when user toggles to Remote). Uses cached lists immediately and refreshes in background.
    func bootstrapDeadlineLists() {
        // Show cached immediately (done in init), now refresh in background:
        Task { await refreshDeadlineOptions(inBackground: true) }
    }

    /// Refreshes pools/groups. If `inBackground` is true, we keep cached lists visible during fetch.
    func refreshDeadlineOptions(inBackground: Bool = true) async {
        // Ensure path
        if settings.deadlineCommandPath.isEmpty, let auto = DeadlineService.detectFromMarker() {
            settings.deadlineCommandPath = auto
        }

        // If we still don't have an executable, mark unavailable but keep cache
        guard FileManager.default.isExecutableFile(atPath: settings.deadlineCommandPath) else {
            if !inBackground {
                deadlineAvailable = false
                deadlineError = "Deadline not found on this Mac."
            }
            saveSettings()
            return
        }

        // Background flag drives a tiny spinner in UI (optional)
        isRefreshingDeadline = true
        let cmd = settings.deadlineCommandPath

        let result = await Task.detached(priority: .userInitiated) { () -> Result<DeadlineService.Lists, Error> in
            do {
                let lists = try DeadlineService.fetchLists(deadlineCmd: cmd)
                return .success(lists)
            } catch {
                return .failure(error)
            }
        }.value

        isRefreshingDeadline = false

        switch result {
        case .success(let lists):
            // Merge new lists (don’t block UI if they were already visible)
            settings.poolOptions  = [""] + lists.pools
            settings.groupOptions = [""] + lists.groups

            // Normalize selections
            if !settings.poolOptions.contains(settings.pool)          { settings.pool = "" }
            if !settings.poolOptions.contains(settings.secondaryPool) { settings.secondaryPool = "" }
            if !settings.groupOptions.contains(settings.group)        { settings.group = "" }

            deadlineAvailable = true
            deadlineError = nil
            settings.lastDeadlineFetch = Date()
            saveSettings()

        case .failure:
            // Keep whatever cache we had; just mark unavailable for new submissions
            if settings.poolOptions.isEmpty && settings.groupOptions.isEmpty {
                deadlineAvailable = false
            }
            if !inBackground {
                deadlineError = "Couldn’t query Deadline. Using cached lists (if any)."
            }
            saveSettings()
        }
    }

    // MARK: Submit

    func submit() {
        saveSettings()
        switch settings.runMode {
        case .remoteDeadline:
            // Allow submit even if lists are cached; Deadline will reject bad combos server-side.
            Encoder.submitToDeadline(items: files, settings: settings)
        case .localFFmpeg:
            Encoder.encodeLocally(items: files, settings: settings)
        }
    }
}
