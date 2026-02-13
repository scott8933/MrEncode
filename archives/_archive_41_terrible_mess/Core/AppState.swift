//
// MARK: - AppState.swift (Refactored)
//

import Foundation
import SwiftUI
import Combine

/// UI state coordinator - delegates business logic to AppCore
final class AppState: ObservableObject {
    
    // Allow non-UI helpers to update file statuses
    static weak var shared: AppState?
    
    // MARK: - Core Business Logic (Delegated)
    private let core = AppCore.shared
    
    // MARK: - UI-Specific State
    @Published var footerHeight: CGFloat = 0
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
    
    // MARK: - Encoding Operations (Delegated)
    
    func submit(items: [MediaItem]) {
        core.submit(items: items)
    }
    
    func submit() {
        let itemsToSubmit = files.filter { $0.status == .queued }
        submit(items: itemsToSubmit)
    }
    
    func cancelAllEncoding() {
        core.cancelAllEncoding()
    }
    
    // MARK: - Status Updates (Delegated)
    
    @MainActor
    func markEncoding(itemID: UUID) {
        core.markEncoding(itemID: itemID)
    }
    
    @MainActor
    func markFinished(itemID: UUID, outputURL: URL) {
        core.markFinished(itemID: itemID, outputURL: outputURL)
    }
    
    @MainActor
    func markError(itemID: UUID, reason: String?) {
        core.markError(itemID: itemID, reason: reason)
    }
    
    func setStatus(_ status: EncodeStatus, forIndex index: Int) {
        core.setStatus(status, forIndex: index)
    }
    
    // MARK: - Estimates (Delegated)
    
    func estimateTotalEncodeSeconds() -> (seconds: Double, count: Int) {
        core.estimateTotalEncodeSeconds()
    }
    
    func formatHMS(_ secs: Double) -> String {
        core.formatHMS(secs)
    }
    
    // MARK: - Logging (Delegated)
    
    func pushMessage(level: LogLevel,
                     _ message: String,
                     filename: String? = nil,
                     code: LogCode? = nil,
                     originKey: String? = nil,
                     detail: String? = nil,
                     jobID: String? = nil,
                     logURL: URL? = nil) {
        core.pushMessage(level: level, message, filename: filename, code: code,
                        originKey: originKey, detail: detail, jobID: jobID, logURL: logURL)
    }
    
    // MARK: - Preset Management (Delegated)
    
    func loadPresets() {
        core.loadPresets()
    }
    
    func applyPreset(name: String) {
        core.applyPreset(name: name)
    }
    
    func saveCurrentAsPreset(name: String) throws {
        try core.saveCurrentAsPreset(name: name)
    }
    
    func deletePreset(name: String) throws {
        try core.deletePreset(name: name)
    }
    
    // MARK: - Droplet Support (Delegated)
    
    func enableDropletMode(presetName: String, exitWhenDone: Bool) {
        core.enableDropletMode(presetName: presetName, exitWhenDone: exitWhenDone)
    }
    
    func exportDroplet(name: String) {
        core.exportDroplet(name: name)
    }
    
    // MARK: - Deadline Support (Delegated)
    
    func bootstrapDeadlineLists() {
        core.bootstrapDeadlineLists()
    }
    
    func refreshDeadlineOptions() {
        core.refreshDeadlineOptions()
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
