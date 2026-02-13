// MrHEVCApp.swift – Minimal fix: keep original SwiftUI architecture, just add file handling
// Uses NSLog for logs (visible in Console.app when not attached to Xcode).

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Carbon // kAEOpenDocuments / keyDirectObject

@main
struct MrHEVCApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup(" ") {
            ContentView()
                .environmentObject(appState)
                .task {
                    if !appState.didBootstrapDeadline {
                        appState.didBootstrapDeadline = true
                        appState.bootstrapDeadlineLists()
                        NSLog("MrHEVC: bootstrapDeadlineLists() ran")
                    }
                }
                .onAppear {
                    AppState.shared = appState
                    FileDropHandler.shared.setAppState(appState)
                }
        }
        .defaultSize(width: 700, height: 900)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // Remove "New Window"
        }
    }
}

// Separate class to handle file drops without interfering with SwiftUI
class FileDropHandler: NSObject {
    static let shared = FileDropHandler()
    private weak var appState: AppState?
    private var hasInstalledHandler = false
    
    override init() {
        super.init()
    }
    
    func setAppState(_ state: AppState) {
        self.appState = state
        installHandlerIfNeeded()
    }
    
    private func installHandlerIfNeeded() {
        guard !hasInstalledHandler else { return }
        hasInstalledHandler = true
        
        // Install Apple Event handler for kAEOpenDocuments
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenDocuments(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )
        
        NSLog("MrHEVC: File drop handler installed")
    }
    
    @objc private func handleOpenDocuments(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        NSLog("MrHEVC: handleOpenDocuments called")
        
        let urls = extractFileURLs(from: event)
        let movUrls = urls.filter { isAllowedQuickTime($0) }
        
        guard !movUrls.isEmpty else {
            NSLog("MrHEVC: No valid .mov files found")
            return
        }
        
        guard let state = appState else {
            NSLog("MrHEVC: No app state available")
            return
        }
        
        DispatchQueue.main.async {
            NSLog("MrHEVC: Adding \(movUrls.count) files to queue")
            state.addFiles(movUrls)
            
            // Bring app to front
            NSApp.activate(ignoringOtherApps: true)
            
            // Let existing UI logic handle auto-encode
            NSLog("MrHEVC: Files added, auto-encode setting: \(state.settings.autoEncodeOnDrop)")
        }
    }
    
    private func extractFileURLs(from event: NSAppleEventDescriptor) -> [URL] {
        var urls: [URL] = []
        guard let direct = event.paramDescriptor(forKeyword: keyDirectObject) else {
            NSLog("MrHEVC: No direct object in Apple Event")
            return []
        }

        if direct.descriptorType == typeAEList {
            NSLog("MrHEVC: Processing AE list with \(direct.numberOfItems) items")
            for i in 1...direct.numberOfItems {
                if let item = direct.atIndex(i), let u = item.fileURLFallback() {
                    urls.append(u)
                }
            }
        } else if let u = direct.fileURLFallback() {
            NSLog("MrHEVC: Processing single AE item")
            urls.append(u)
        }
        
        NSLog("MrHEVC: Extracted \(urls.count) URLs")
        return urls
    }
    
    private func isAllowedQuickTime(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type == .quickTimeMovie || type.conforms(to: .quickTimeMovie)
        }
        return url.pathExtension.lowercased() == "mov"
    }
}

// File URL extraction helper
private extension NSAppleEventDescriptor {
    func fileURLFallback() -> URL? {
        // 1) Modern API: try fileURLValue if available
        if responds(to: NSSelectorFromString("fileURLValue")),
           let val = perform(NSSelectorFromString("fileURLValue"))?.takeUnretainedValue() as? URL {
            return val
        }

        // 2) Plain string path
        if let path = stringValue, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        // 3) Coerce to typeFileURL and reinterpret bytes
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
