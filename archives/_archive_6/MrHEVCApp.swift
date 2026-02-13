// MrHEVCApp.swift — SwiftUI-only entry (no NSApplicationDelegate).
// Dock/Finder .mov open → auto-encode; single-window (no reset); quit-on-close.

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Carbon // kAEOpenDocuments / keyDirectObject

// Distributed notification used to forward open-file events between instances
private extension Notification.Name {
    static let mrhevcOpenDocs = Notification.Name("MrHEVC.OpenDocs")
}

@main
struct MrHEVCApp: App {
    @StateObject private var appState = AppState()
    private let router = OpenDocsRouter()   // does NOT touch appState in init

    var body: some Scene {
        WindowGroup(" ") {
            ContentView()
                .environmentObject(appState)
                // Run Deadline bootstrap ONCE (prevents “re-connect” feel)
                .task {
                    if !appState.didBootstrapDeadline {
                        appState.didBootstrapDeadline = true
                        appState.bootstrapDeadlineLists()
                    }
                }
                .onAppear {
                    // Safe to touch StateObject now
                    if AppState.shared == nil { AppState.shared = appState }
                    router.appState = appState   // flush any early Dock drops
                }
        }
        // IMPORTANT: Route external events (file opens) to THIS scene instead of spawning a new one.
        .handlesExternalEvents(matching: Set(["*"]))
        .defaultSize(width: 700, height: 900)
        .windowResizability(.contentSize)
    }
}

// MARK: - OpenDocsRouter (no AppDelegate)
final class OpenDocsRouter: NSObject {

    weak var appState: AppState? { didSet { flushPendingIfNeeded() } }
    private var pending: [URL] = []

    override init() {
        super.init()
        installOpenDocumentsHandler()
        installForwardedOpenObserver()
        installQuitOnClose()
        print("MrHEVC launching from:", Bundle.main.bundlePath)
    }

    deinit {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID:    AEEventID(kAEOpenDocuments)
        )
        DistributedNotificationCenter.default().removeObserver(self, name: .mrhevcOpenDocs, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
    }

    // Apple Event: kAEOpenDocuments (Dock/Finder)
    private func installOpenDocumentsHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenDocumentsEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID:    AEEventID(kAEOpenDocuments)
        )
    }

    @objc private func handleOpenDocumentsEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        let urls = extractFileURLs(from: event)
        route(urls: urls, forwarded: false)
    }

    // Forwarded open-docs (from another instance)
    private func installForwardedOpenObserver() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleForwardedOpen(_:)),
            name: .mrhevcOpenDocs,
            object: nil
        )
    }

    @objc private func handleForwardedOpen(_ note: Notification) {
        let paths = (note.userInfo?["urls"] as? [String]) ?? []
        route(urls: paths.map { URL(fileURLWithPath: $0) }, forwarded: true)
    }

    // Quit when last window closes (no AppDelegate)
    private func installQuitOnClose() {
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.async {
                if !NSApp.windows.contains(where: { $0.isVisible }) { NSApp.terminate(nil) }
            }
        }
    }

    // Core routing
    private func route(urls: [URL], forwarded: Bool) {
        let movs = urls.filter(Self.isAllowedQuickTime)
        guard !movs.isEmpty else { return }

        // If this is a new instance and another with same bundle id is running, forward and quit.
        if !forwarded, let _ = otherRunningInstance() {
            let paths = movs.map(\.path)
            DistributedNotificationCenter.default().post(
                name: .mrhevcOpenDocs,
                object: Bundle.main.bundleIdentifier ?? "",
                userInfo: ["urls": paths]
            )
            NSApp.terminate(nil)    // quit the stray instance immediately
            return
        }

        // Process here (primary instance or forwarded URLs)
        guard let state = appState else {
            pending.append(contentsOf: movs)  // buffer until appState is available
            return
        }

        state.addFiles(movs)

        // Submit on next runloop tick so queued statuses are published → reliable auto-encode.
        DispatchQueue.main.async {
            state.submit()           // treat Dock drop as auto-encode
            // Bring the existing window forward without touching view lifecycle
            if let keyWin = NSApp.keyWindow {
                keyWin.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func flushPendingIfNeeded() {
        guard let state = appState, !pending.isEmpty else { return }
        let urls = pending; pending.removeAll()
        state.addFiles(urls)
        DispatchQueue.main.async {
            state.submit()
            if let keyWin = NSApp.keyWindow {
                keyWin.orderFrontRegardless()
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // Helpers

    private func otherRunningInstance() -> NSRunningApplication? {
        let myPID = NSRunningApplication.current.processIdentifier
        let myID  = Bundle.main.bundleIdentifier ?? ""
        return NSRunningApplication.runningApplications(withBundleIdentifier: myID)
            .first(where: { $0.processIdentifier != myPID })
    }

    /// UTType-aware .mov check
    private static func isAllowedQuickTime(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type == .quickTimeMovie || type.conforms(to: .quickTimeMovie)
        }
        return url.pathExtension.lowercased() == "mov"
    }

    /// Extract file URLs from kAEOpenDocuments Apple Event.
    private func extractFileURLs(from event: NSAppleEventDescriptor) -> [URL] {
        var urls: [URL] = []
        guard let direct = event.paramDescriptor(forKeyword: keyDirectObject) else { return [] }

        if direct.descriptorType == typeAEList {
            for i in 1...direct.numberOfItems {
                if let item = direct.atIndex(i), let u = item.fileURLFallback() { urls.append(u) }
            }
        } else if let u = direct.fileURLFallback() {
            urls.append(u)
        }
        return urls
    }
}

// Try to extract a URL from an AppleEvent descriptor (works across SDKs)
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
