//
// MARK: - AppState.swift (Revised - Removed footerHeight)
//

import Foundation
import SwiftUI
import Combine

/// UI state coordinator - delegates business logic to AppCore
final class AppState: ObservableObject {
    
    // MARK: - Queue maintenance (UI convenience)
    func clearAll() {
        // Mirrors previous behavior: clear everything that isn't actively encoding
        clearAllNonEncoding()
    }
    
    // Allow non-UI helpers to update file statuses
    static weak var shared: AppState?
    
    // MARK: - Core Business Logic (Delegated)
    private let core = AppCore.shared
    
    // MARK: - UI-Specific State
    // REMOVED: @Published var footerHeight: CGFloat = 0  // No longer needed with new layout
    @Published var selectedIDs: Set<MediaItem.ID> = []
    @Published var showPreferences: Bool = false
    
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
    
    // MARK: - Encoding Service Delegation
    var isGloballyPaused: Bool {
        get { EncodingService.shared.isGloballyPaused }
        set { EncodingService.shared.isGloballyPaused = newValue }
    }
    
    init() {
        AppState.shared = self
        
        // Set up change propagation from core to UI
        core.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        
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
    
    // MARK: - Selection Helper
    
    func selectedItemsOrAll() -> [MediaItem] {
        selectedIDs.isEmpty ? files : files.filter { selectedIDs.contains($0.id) }
    }
    
    func toggleSelection(for id: MediaItem.ID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
    
    func selectAll() {
        selectedIDs = Set(files.map(\.id))
    }
    
    func selectNone() {
        selectedIDs.removeAll()
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

        #if DEBUG
        print("[DropletExport] runMode=\(dropletSettings.runMode) pool=\(dropletSettings.pool) secondary=\(dropletSettings.secondaryPool) group=\(dropletSettings.group)")
        #endif

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
