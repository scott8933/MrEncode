// MrEncodeApp.swift — Complete file with CLI support + existing functionality
// Replace the entire MrEncodeApp.swift file with this content

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Carbon


struct MrEncodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @State private var didHandleStartupArgs = false
    
    var body: some Scene {
        WindowGroup(" ") {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.settings.uiTheme.toColorScheme())
                .task {
                    if !appState.didBootstrapDeadline {
                        appState.bootstrapDeadlineLists()
                        NSLog("MrEncode: bootstrapDeadlineLists() ran")
                    }
                }
                .onAppear {
                    AppState.shared = appState
                    FileDropHandler.shared.setAppState(appState)
                    appState.settings.coerceDropdownDefaultsTopFirst()

                    // Run once per launch.
                    guard !didHandleStartupArgs else { return }
                    didHandleStartupArgs = true

                    // New: run-request mode (preferred)
                    handleRunRequestMode()

                    // Legacy: --droplet mode (keep temporarily)
                    handleDropletMode()
                }
        }
        .defaultSize(width: 700, height: 900)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
        
        .commands {
            MrEncodeCommands()
        }

        // Single-instance Help window (standard Help menu entry)
        #if os(macOS)
        Window("Help", id: "help") {
            UI_HelpView()
                .environmentObject(appState)
                .padding(12)
        }
        .defaultSize(width: 820, height: 620)
        #endif

        // Single-instance Log Viewer window (macOS)
        #if os(macOS)
        Window("Log", id: "log-viewer") {
            UI_MessageArea(presentation: .window)
                .environmentObject(appState)
                .padding(12)
        }
        .defaultSize(width: 900, height: 520)
        #endif
    }
    
    
    
    // MARK: - GUI Run Request Mode (new, preferred)

    private func handleRunRequestMode() {
        guard let (requestPath, request) = RunRequestLoader.consumeIfPresent() else { return }

        // One-shot: remove the run request file so it can't re-run on next launch
        try? FileManager.default.removeItem(atPath: requestPath)


        NSLog("MrEncode: RunRequest mode detected - preset: \(request.presetName), inputs: \(request.inputPaths.count)")

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .deferredToDate

            guard let data = request.presetJSON.data(using: .utf8) else {
                throw NSError(domain: "MrEncode", code: 1002, userInfo: [
                    NSLocalizedDescriptionKey: "presetJSON was not valid UTF-8"
                ])
            }

            let env = try decoder.decode(PresetEnvelope.self, from: data)

            // Persist/update preset locally using the decoded Settings snapshot
            try PresetManager.shared.savePreset(name: request.presetName, settings: env.settings)
            
            NSLog("MrEncode: RunRequest preset persisted: %@", request.presetName)

        } catch {
            NSLog("MrEncode: Failed to decode/persist RunRequest preset '\(request.presetName)': \(error)")
        }

        // Enable droplet mode in the UI (uses presetName, exit semantics)
        Task(priority: .userInitiated) {
            await MainActor.run {
                self.appState.enableDropletMode(
                    presetName: request.presetName,
                    exitWhenDone: true // request.autoQuitOnCompletion
                )
            }
        }

        // Import input paths
        let urls = request.inputPaths.map { URL(fileURLWithPath: $0) }

        // Snapshot IDs before import
        let beforeIDs = Set(self.appState.files.map(\.id))

        // Import (may synchronously add items; folder expansion may continue asynchronously)
        self.appState.addFiles(urls)

        // Tag items added immediately
        do {
            let afterIDs = Set(self.appState.files.map(\.id))
            let newIDs = afterIDs.subtracting(beforeIDs)
            self.appState.setIngestGroupID(request.ingestGroupID, forMediaIDs: newIDs)
        }

        // Helper: items belonging to this ingest group
        func groupItems() -> [MediaItem] {
            self.appState.files.filter { $0.ingestGroupID == request.ingestGroupID }
        }

        // Phase 1: settle window (tags items that appear shortly after addFiles due to folder expansion)
        let settleDeadline = Date().addingTimeInterval(3.0)
        var knownIDs = Set(self.appState.files.map(\.id))

        func settleTick() {
            // Tag anything newly appeared since last tick
            let currentIDs = Set(self.appState.files.map(\.id))
            let newlyAppeared = currentIDs.subtracting(knownIDs)
            if !newlyAppeared.isEmpty {
                self.appState.setIngestGroupID(request.ingestGroupID, forMediaIDs: newlyAppeared)
                knownIDs = currentIDs
            }

            if Date() < settleDeadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    settleTick()
                }
                return
            }

            // Decide what to do after settling
            let items = groupItems()

            // Skip-only drop: nothing importable was added → quit.
            if items.isEmpty {
                NSLog("MrEncode: Ingest group \(request.ingestGroupID) imported 0 media; quitting (skip policy).")
                NSApp.terminate(nil)
                return
            }

            // Auto-start only if this group has queued+checked items.
            let readyToEncode = items.contains { $0.status == .queued && $0.isChecked }
            if readyToEncode {
                self.appState.submit()
            } else {
                NSLog("MrEncode: Ingest group \(request.ingestGroupID) has no queued+checked media; quitting.")
                NSApp.terminate(nil)
                return
            }

            // Phase 2: monitor completion and quit when terminal
            func completionTick() {
                let now = groupItems()

                if now.isEmpty {
                    NSLog("MrEncode: Ingest group \(request.ingestGroupID) items disappeared; quitting.")
                    NSApp.terminate(nil)
                    return
                }

                if now.allSatisfy({ isTerminal($0.status) }) {
                    NSLog("MrEncode: Ingest group \(request.ingestGroupID) complete; quitting.")
                    NSApp.terminate(nil)
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    completionTick()
                }
            }

            completionTick()
        }

        settleTick()

    }


    private func isTerminal(_ status: EncodeStatus) -> Bool {
        switch status {
        case .done, .error, .blocked:
            return true
        case .queued, .encoding:
            return false
        }
    }

    

    
    private func handleDropletMode() {
        let arguments = CommandLine.arguments
        
        // Only handle GUI droplet mode (no --cli flag)
        guard !arguments.contains("--cli") else { return }
        
        guard let dropletIndex = arguments.firstIndex(of: "--droplet"),
              dropletIndex + 1 < arguments.count else {
            return // Not droplet mode
        }
        
        let dropletFilePath = arguments[dropletIndex + 1]
        let videoFilePaths = Array(arguments[(dropletIndex + 2)...])
        
        NSLog("MrEncode: GUI Droplet mode detected - preset: \(dropletFilePath), files: \(videoFilePaths)")
        
        // Load droplet settings
        do {
            let dropletURL = URL(fileURLWithPath: dropletFilePath)
            let dropletData = try Data(contentsOf: dropletURL)
            let dropletFile = try JSONDecoder().decode(DropletFile.self, from: dropletData)
            
            // Enter droplet mode on main actor
            Task(priority: .userInitiated) { @MainActor in
                AppState.shared?.enableDropletMode(presetName: dropletFile.presetName, exitWhenDone: true)
            }

            // Add video files to queue
            let videoURLs = videoFilePaths.compactMap { path in
                let url = URL(fileURLWithPath: path)
                return url.pathExtension.lowercased() == "mov" ? url : nil
            }
            
            if !videoURLs.isEmpty {
                Task(priority: .userInitiated) { @MainActor in
                    self.appState.addFiles(videoURLs)
                    // Auto-start encoding after UI is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let readyToEncode = self.appState.files.contains { $0.status == .queued && $0.isChecked }
                        if readyToEncode {
                            self.appState.submit()
                        }
                    }
                }
            }
            
        } catch {
            NSLog("MrEncode: Failed to load droplet: \(error)")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Droplet Error"
                alert.informativeText = "Could not load droplet settings: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

// MARK: - File Drop Handler (existing code, kept as-is)

final class FileDropHandler: NSObject {
    static let shared = FileDropHandler()

    private weak var appState: AppState?
    private var pending: [URL] = []

    override init() {
        super.init()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenDocuments(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID:    AEEventID(kAEOpenDocuments)
        )
        NSLog("MrEncode: File drop handler installed")
    }

    func setAppState(_ state: AppState) {
        self.appState = state
        if !pending.isEmpty {
            let urls = pending
            pending.removeAll()
            processURLs(urls, into: state)
            NSLog("MrEncode: flushed \(urls.count) buffered url(s)")
        }
    }

    @objc private func handleOpenDocuments(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        NSLog("MrEncode: handleOpenDocuments called")
        let urls = extractFileURLs(from: event)
        
        if let state = appState {
            processURLs(urls, into: state)
        } else {
            pending.append(contentsOf: urls)
            NSLog("MrEncode: buffered \(urls.count) url(s) (state not ready)")
        }
    }

    private func processURLs(_ urls: [URL], into state: AppState) {
        var dropletFiles: [URL] = []
        var videoFiles: [URL] = []
        
        for url in urls {
            if url.pathExtension.lowercased() == "mrencode" {
                dropletFiles.append(url)
            } else if isDecodableVideo(url) {
                videoFiles.append(url)
            }
        }
        
        DispatchQueue.main.async {
            if let dropletURL = dropletFiles.first {
                self.handleDropletFile(dropletURL, into: state)
            }
            
            if !videoFiles.isEmpty {
                self.enqueueVideoFiles(videoFiles, into: state)
            }

            if let key = NSApp.keyWindow { key.orderFrontRegardless() }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func handleDropletFile(_ url: URL, into state: AppState) {
        do {
            let dropletFile = try PresetManager.shared.loadDroplet(from: url)
            Task(priority: .userInitiated) { @MainActor in
                state.enableDropletMode(presetName: dropletFile.presetName, exitWhenDone: true)
            }
            NSLog("MrEncode: Loaded droplet: \(dropletFile.presetName)")
        } catch {
            NSLog("MrEncode: Failed to load droplet: \(error)")
            
            let alert = NSAlert()
            alert.messageText = "Invalid Droplet File"
            alert.informativeText = "Could not load droplet file: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func enqueueVideoFiles(_ urls: [URL], into state: AppState) {
        NSLog("MrEncode: Adding \(urls.count) video file(s) to queue")
        Task(priority: .userInitiated) { @MainActor in
            state.addFiles(urls)

            if state.settings.autoEncodeOnDrop,
               state.files.contains(where: { $0.status == .queued }) {
                NSLog("MrEncode: Auto-Encode is ON → submitting")
                state.submit()
            } else {
                NSLog("MrEncode: Auto-Encode is OFF → not submitting")
            }
        }
    }

    private func extractFileURLs(from event: NSAppleEventDescriptor) -> [URL] {
        var urls: [URL] = []
        guard let direct = event.paramDescriptor(forKeyword: keyDirectObject) else {
            NSLog("MrEncode: No direct object in Apple Event")
            return []
        }
        if direct.descriptorType == typeAEList {
            NSLog("MrEncode: AE list with \(direct.numberOfItems) items")
            for i in 1...direct.numberOfItems {
                if let item = direct.atIndex(i), let u = item.fileURLFallback() { urls.append(u) }
            }
        } else if let u = direct.fileURLFallback() {
            NSLog("MrEncode: Single AE item")
            urls.append(u)
        }
        NSLog("MrEncode: Extracted \(urls.count) URL(s)")
        return urls
    }

    private func isDecodableVideo(_ url: URL) -> Bool {
            let probe = MediaProbeService.probeVideoDecode(url)
            return probe.hasVideo && probe.canDecode
        }
}

private extension UIThemeSelection {
    func toColorScheme() -> ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// File URL extraction helper (SDK-tolerant)
private extension NSAppleEventDescriptor {
    func fileURLFallback() -> URL? {
        if responds(to: NSSelectorFromString("fileURLValue")),
           let val = perform(NSSelectorFromString("fileURLValue"))?.takeUnretainedValue() as? URL {
            return val
        }
        if let path = stringValue, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        guard let coerced = coerce(toDescriptorType: typeFileURL) else { return nil }
        let data: Data = coerced.data
        if data.isEmpty { return nil }
        return data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            return (CFURLCreateWithBytes(
                kCFAllocatorDefault,
                base,
                rawBuf.count,
                CFStringBuiltInEncodings.UTF8.rawValue,
                nil
            ) as URL?)
        }
    }
}

