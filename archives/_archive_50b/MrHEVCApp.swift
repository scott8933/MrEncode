// MrHEVCApp.swift — Complete file with CLI support + existing functionality
// Replace the entire MrHEVCApp.swift file with this content

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Carbon

@main
struct MrHEVCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    init() {
        // Check if we should run in CLI mode
        if shouldRunInCLIMode() {
            let exitCode = DropletRunner.run(arguments: CommandLine.arguments)
            exit(Int32(exitCode))
        }
    }

    var body: some Scene {
        WindowGroup("MrHEVC") {   // internal title; won’t show in the chrome
            ContentView()
                .environmentObject(appState)
                .task {
                    if !appState.didBootstrapDeadline {
                        appState.bootstrapDeadlineLists()
                        NSLog("MrHEVC: bootstrapDeadlineLists() ran")
                    }
                }
                .onAppear {
                    AppState.shared = appState
                    FileDropHandler.shared.setAppState(appState)
                    appState.settings.coerceDropdownDefaultsTopFirst()

                    // Only handle droplet mode if we're in GUI mode
                    handleDropletMode()
                }
        }
        .windowStyle(.hiddenTitleBar)        // hides visible title, keeps stoplights
        .windowToolbarStyle(.unifiedCompact) // puts toolbar on same strip as stoplights
    }


    // MARK: - CLI Mode Detection and Execution
    
    private func shouldRunInCLIMode() -> Bool {
        let arguments = CommandLine.arguments
        return arguments.contains("--cli")
    }
    
    
    // MARK: - GUI Droplet Mode (existing functionality)
    
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
        
        NSLog("MrHEVC: GUI Droplet mode detected - preset: \(dropletFilePath), files: \(videoFilePaths)")
        
        // Load droplet settings
        do {
            let dropletURL = URL(fileURLWithPath: dropletFilePath)
            let dropletData = try Data(contentsOf: dropletURL)
            let dropletFile = try JSONDecoder().decode(DropletFile.self, from: dropletData)
            
            // Enter droplet mode
            AppState.shared?.enableDropletMode(presetName: dropletFile.presetName, exitWhenDone: true)

            // Add video files to queue
            let videoURLs = videoFilePaths.compactMap { path in
                let url = URL(fileURLWithPath: path)
                return url.pathExtension.lowercased() == "mov" ? url : nil
            }
            
            if !videoURLs.isEmpty {
                appState.addFiles(videoURLs)
                
                // Auto-start encoding after UI is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let readyToEncode = self.appState.files.contains { $0.status == .queued && $0.isChecked }
                    if readyToEncode {
                        self.appState.submit()
                    }
                }
            }
            
        } catch {
            NSLog("MrHEVC: Failed to load droplet: \(error)")
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
        NSLog("MrHEVC: File drop handler installed")
    }

    func setAppState(_ state: AppState) {
        self.appState = state
        if !pending.isEmpty {
            let urls = pending
            pending.removeAll()
            processURLs(urls, into: state)
            NSLog("MrHEVC: flushed \(urls.count) buffered url(s)")
        }
    }

    @objc private func handleOpenDocuments(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        NSLog("MrHEVC: handleOpenDocuments called")
        let urls = extractFileURLs(from: event)
        
        if let state = appState {
            processURLs(urls, into: state)
        } else {
            pending.append(contentsOf: urls)
            NSLog("MrHEVC: buffered \(urls.count) url(s) (state not ready)")
        }
    }

    private func processURLs(_ urls: [URL], into state: AppState) {
        var dropletFiles: [URL] = []
        var videoFiles: [URL] = []
        
        for url in urls {
            if url.pathExtension.lowercased() == "mrhevc" {
                dropletFiles.append(url)
            } else if isAllowedQuickTime(url) {
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
            state.enableDropletMode(presetName: dropletFile.presetName, exitWhenDone: true)
            NSLog("MrHEVC: Loaded droplet: \(dropletFile.presetName)")
        } catch {
            NSLog("MrHEVC: Failed to load droplet: \(error)")
            
            let alert = NSAlert()
            alert.messageText = "Invalid Droplet File"
            alert.informativeText = "Could not load droplet file: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func enqueueVideoFiles(_ urls: [URL], into state: AppState) {
        NSLog("MrHEVC: Adding \(urls.count) video file(s) to queue")
        state.addFiles(urls)

        if state.settings.autoEncodeOnDrop,
           state.files.contains(where: { $0.status == .queued }) {
            NSLog("MrHEVC: Auto-Encode is ON → submitting")
            state.submit()
        } else {
            NSLog("MrHEVC: Auto-Encode is OFF → not submitting")
        }
    }

    private func extractFileURLs(from event: NSAppleEventDescriptor) -> [URL] {
        var urls: [URL] = []
        guard let direct = event.paramDescriptor(forKeyword: keyDirectObject) else {
            NSLog("MrHEVC: No direct object in Apple Event")
            return []
        }
        if direct.descriptorType == typeAEList {
            NSLog("MrHEVC: AE list with \(direct.numberOfItems) items")
            for i in 1...direct.numberOfItems {
                if let item = direct.atIndex(i), let u = item.fileURLFallback() { urls.append(u) }
            }
        } else if let u = direct.fileURLFallback() {
            NSLog("MrHEVC: Single AE item")
            urls.append(u)
        }
        NSLog("MrHEVC: Extracted \(urls.count) URL(s)")
        return urls
    }

    private func isAllowedQuickTime(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type == .quickTimeMovie || type.conforms(to: .quickTimeMovie)
        }
        return url.pathExtension.lowercased() == "mov"
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
