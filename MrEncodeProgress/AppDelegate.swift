//
//  AppDelegate.swift
//  MrEncodeProgress
//
//  Created by scott ulrich on 2/5/26.
//

import Cocoa
import Foundation

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var wc: ProgressWindowController?

    // CRITICAL: This is what makes the window appear
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let args = ProgressAppArgs.parse() else {
            NSApp.terminate(nil)
            return
        }

        wc = ProgressWindowController(
            progressFile: args.progressFileURL,
            chimeVolume: args.chimeVolume
        )

        // Force window creation
        wc?.loadWindow()

        DispatchQueue.main.async {
            guard let w = self.wc?.window else { return }
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }

        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Arg parsing

private struct ProgressAppArgs {
    let progressFileURL: URL
    let chimeVolume: Double

    static func parse(_ argv: [String] = CommandLine.arguments) -> ProgressAppArgs? {
        func value(after flag: String) -> String? {
            guard let i = argv.firstIndex(of: flag), i + 1 < argv.count else { return nil }
            return argv[i + 1]
        }

        guard let path = value(after: "--progress-file") else { return nil }

        let volRaw = Double(value(after: "--chime-volume") ?? "") ?? 0.30
        let vol = min(max(volRaw, 0.0), 1.0)

        return .init(progressFileURL: URL(fileURLWithPath: path), chimeVolume: vol)
    }
}

// MARK: - Window controller

final class ProgressWindowController: NSWindowController {

    private let tailer: ProgressTailer
    private let chimeVolume: Double

    private let statusLabel = NSTextField(labelWithString: "Starting…")
    private let etaLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "0%")
    private let bar = NSProgressIndicator()

    private var didFinish = false
    private var didPlayDoneChime = false
    
    private var activeSound: NSSound?


    override func windowDidLoad() {
        super.windowDidLoad()
        window?.center()
    }

    init(progressFile: URL, chimeVolume: Double) {
        self.chimeVolume = (chimeVolume <= 0 ? 0.30 : min(max(chimeVolume, 0.0), 1.0))
        self.tailer = ProgressTailer(url: progressFile)
        super.init(window: nil)
        buildUI()
        wire()
        tailer.start()
    }

    required init?(coder: NSCoder) { nil }

    private func buildUI() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "MrEncode"
        w.isReleasedWhenClosed = false
        w.center()
        self.window = w

        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear

        etaLabel.font = .systemFont(ofSize: 12, weight: .regular)
        etaLabel.textColor = .secondaryLabelColor
        etaLabel.isEditable = false
        etaLabel.isBordered = false
        etaLabel.backgroundColor = .clear

        percentLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        percentLabel.alignment = .right
        percentLabel.isEditable = false
        percentLabel.isBordered = false
        percentLabel.backgroundColor = .clear
        percentLabel.setContentHuggingPriority(.required, for: .horizontal)

        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        bar.doubleValue = 0
        bar.heightAnchor.constraint(equalToConstant: 12).isActive = true

        let row = NSStackView(views: [bar, percentLabel])
        row.orientation = .horizontal
        row.spacing = 10

        let stack = NSStackView(views: [statusLabel, etaLabel, row])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        w.contentView = content

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
        ])
    }

    private func wire() {
        tailer.onEvent = { [weak self] ev in
            DispatchQueue.main.async { self?.apply(ev) }
        }

        // IMPORTANT: this requires the small ProgressTailer change described below.
        tailer.onBatchDone = { [weak self] ok in
            DispatchQueue.main.async { self?.applyBatchDone(ok: ok) }
        }
    }

    func apply(_ ev: ProgressEvent) {
        guard !didFinish else { return }

        switch ev.type.lowercased() {
        case "progress":
            if let msg = ev.message, !msg.isEmpty {
                statusLabel.stringValue = msg
            }

            let f = max(0.0, min(1.0, ev.fraction ?? 0))
            let pct = Int((f * 100).rounded())
            bar.doubleValue = Double(pct)
            percentLabel.stringValue = "\(pct)%"

            if let eta = ev.eta, eta.isFinite, eta > 0 {
                etaLabel.stringValue = "ETA \(formatETA(eta))"
            } else {
                etaLabel.stringValue = ""
            }

        case "file_done":
            // File-level completion only. Do NOT finish batch here.
            if ev.ok == false {
                statusLabel.stringValue = ev.message?.isEmpty == false ? ev.message! : "File failed"
                etaLabel.stringValue = ""
            }

        default:
            break
        }
    }

    private func applyBatchDone(ok: Bool) {
        guard !didFinish else { return }
        didFinish = true

        if ok {
            statusLabel.stringValue = "Done"
            bar.doubleValue = 100
            percentLabel.stringValue = "100%"
            etaLabel.stringValue = ""
            playDoneSoundOnce()
        } else {
            statusLabel.stringValue = "Failed"
            etaLabel.stringValue = ""
        }

        autoCloseSoon()
    }

    private func autoCloseSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.window?.close()
            NSApp.terminate(nil)
        }
    }

    private func playDoneSoundOnce() {
        guard !didPlayDoneChime else { return }
        didPlayDoneChime = true

        // 1) Bundled chime (your actual filename)
        if let url = Bundle.main.url(forResource: "MrEncode_DONE", withExtension: "wav"),
           let s = NSSound(contentsOf: url, byReference: false) {
            s.volume = Float(chimeVolume)
            activeSound = s
            s.play()

            // Keep it alive long enough to play
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.activeSound = nil
            }
            return
        }

        // 2) Fallback system sound so you *always* hear something during debugging
        if let s = NSSound(named: NSSound.Name("Glass")) {
            s.volume = Float(chimeVolume)
            activeSound = s
            s.play()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.activeSound = nil
            }
        }
    }


    private func formatETA(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}
