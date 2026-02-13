// MrHEVCApp.swift – robust first-drop handling + unified auto-encode
// Installs kAEOpenDocuments handler at startup, buffers early events, flushes on state ready.

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Carbon // kAEOpenDocuments / keyDirectObject

@main
struct MrHEVCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
                    // Make state visible globally (if you use AppState.shared elsewhere)
                    AppState.shared = appState
                    // Provide state to the drop handler (flushes any early, buffered drops)
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

// MARK: - Apple Event drop handler (installs immediately, buffers early events)
final class FileDropHandler: NSObject {
    static let shared = FileDropHandler()

    private weak var appState: AppState?
    private var pending: [URL] = []

    override init() {
        super.init()
        // Install Apple Event handler right away so FIRST Dock/Finder drop is caught.
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
        // Flush any drops that arrived before the UI/state was ready
        if !pending.isEmpty {
            let urls = pending
            pending.removeAll()
            enqueue(urls, into: state)
            NSLog("MrHEVC: flushed \(urls.count) buffered url(s)")
        }
    }

    @objc private func handleOpenDocuments(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        NSLog("MrHEVC: handleOpenDocuments called")
        let urls = extractFileURLs(from: event)
        let movs = urls.filter { isAllowedQuickTime($0) }
        guard !movs.isEmpty else {
            NSLog("MrHEVC: No valid .mov files in event")
            return
        }
        if let state = appState {
            enqueue(movs, into: state)
        } else {
            // UI/state not ready yet — buffer and flush on setAppState
            pending.append(contentsOf: movs)
            NSLog("MrHEVC: buffered \(movs.count) url(s) (state not ready)")
        }
    }

    // Add to queue; optionally auto-start depending on the user’s setting.
    private func enqueue(_ urls: [URL], into state: AppState) {
        DispatchQueue.main.async {
            NSLog("MrHEVC: Adding \(urls.count) file(s) to queue")
            state.addFiles(urls)

            // Respect the Auto-Encode toggle
            if state.settings.autoEncodeOnDrop,
               state.files.contains(where: { $0.status == .queued }) {
                NSLog("MrHEVC: Auto-Encode is ON → submitting")
                state.submit()
            } else {
                NSLog("MrHEVC: Auto-Encode is OFF → not submitting")
            }

            // Bring app to front
            if let key = NSApp.keyWindow { key.orderFrontRegardless() }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // --- Helpers ---

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
