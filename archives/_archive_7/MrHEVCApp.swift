// MrHEVCApp.swift – Back to your original working code
// The ONLY fix needed is the Info.plist document types

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
    private let router = OpenDocsRouter()

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
                    if AppState.shared == nil { AppState.shared = appState }
                    router.appState = appState
                }
                .background(WindowAccessor(id: "MainWindow"))
        }
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
        NSLog("MrHEVC launching from: \(Bundle.main.bundlePath)")
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
        NSLog("MrHEVC: Apple Event received - handleOpenDocumentsEvent")
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

    // Core routing - SIMPLIFIED
    private func route(urls: [URL], forwarded: Bool) {
        let movs = urls.filter(Self.isAllowedQuickTime)
        guard !movs.isEmpty else {
            NSLog("MrHEVC: No valid .mov files found")
            return
        }

        if !forwarded, let _ = otherRunningInstance() {
            let paths = movs.map(\.path)
            DistributedNotificationCenter.default().post(
                name: .mrhevcOpenDocs,
                object: Bundle.main.bundleIdentifier ?? "",
                userInfo: ["urls": paths]
            )
            NSLog("MrHEVC: forwarded \(paths.count) paths to primary instance; terminating extra instance")
            NSApp.terminate(nil)
            return
        }

        guard let state = appState else {
            pending.append(contentsOf: movs)
            NSLog("MrHEVC: buffered \(movs.count) urls (state not ready)")
            return
        }

        // Simply add files to queue
        state.addFiles(movs)
        NSLog("MrHEVC: Added \(movs.count) files to queue: \(movs.map { $0.lastPathComponent })")

        // Bring app to front
        bringMainWindowToFront()
        
        // Log the auto-encode setting but don't force anything
        NSLog("MrHEVC: Auto-encode setting: \(state.settings.autoEncodeOnDrop)")
    }

    private func flushPendingIfNeeded() {
        guard let state = appState, !pending.isEmpty else { return }
        let urls = pending; pending.removeAll()
        state.addFiles(urls)
        NSLog("MrHEVC: flushed \(urls.count) buffered url(s)")
        bringMainWindowToFront()
    }

    private func bringMainWindowToFront() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let main = NSApp.windows.first(where: { $0.identifier?.rawValue == "MainWindow" }) {
                main.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func otherRunningInstance() -> NSRunningApplication? {
        let myPID = NSRunningApplication.current.processIdentifier
        let myID  = Bundle.main.bundleIdentifier ?? ""
        return NSRunningApplication.runningApplications(withBundleIdentifier: myID)
            .first(where: { $0.processIdentifier != myPID })
    }

    private static func isAllowedQuickTime(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type == .quickTimeMovie || type.conforms(to: .quickTimeMovie)
        }
        return url.pathExtension.lowercased() == "mov"
    }

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

// Try to extract a URL from an AppleEvent descriptor
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

// MARK: - Single-window helper
private enum WindowRegistry {
    static weak var main: NSWindow?
}

private struct WindowAccessor: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let win = v.window else { return }
            win.identifier = NSUserInterfaceItemIdentifier(id)

            if WindowRegistry.main == nil {
                WindowRegistry.main = win
                win.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            if let main = WindowRegistry.main, win !== main {
                win.orderOut(nil)
                win.close()
                main.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
