// =============================
// File: DropletProgressWindow
// =============================


import AppKit

private final class DropletProgressPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Lightweight floating progress window used by CLI droplets while encoding locally.
final class DropletProgressWindow {
    private var window: NSWindow?
    private let messageLabel = NSTextField(labelWithString: "")
    private let progressIndicator: NSProgressIndicator = {
        let indicator = NSProgressIndicator()
        indicator.isIndeterminate = true
        indicator.controlSize = .regular
        indicator.style = .bar
        indicator.usesThreadedAnimation = true
        indicator.startAnimation(nil)
        return indicator
    }()
    private var totalSeconds: Double?
    private var cancelButton: NSButton?
    private var cancelHandler: (() -> Void)?
    private var originalPolicy: NSApplication.ActivationPolicy?

    func show(fileName: String, cancelHandler: @escaping () -> Void) {
        let work = {
            guard self.window == nil else { return }

            let app = NSApplication.shared
            self.originalPolicy = app.activationPolicy()
            app.setActivationPolicy(.regular)
            app.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])

            let contentSize = NSSize(width: 360, height: 160)
            let panel = DropletProgressPanel(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Encoding…"
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.center()
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true

            let contentView = NSView(frame: NSRect(origin: .zero, size: contentSize))
            panel.contentView = contentView

            self.messageLabel.stringValue = "Processing \(fileName)"
            self.messageLabel.font = .systemFont(ofSize: 14)
            self.messageLabel.alignment = .center
            self.messageLabel.translatesAutoresizingMaskIntoConstraints = false

            self.progressIndicator.translatesAutoresizingMaskIntoConstraints = false

            let button = NSButton(title: "Cancel", target: self, action: #selector(self.didPressCancel))
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            self.cancelButton = button
            self.cancelHandler = cancelHandler

            contentView.addSubview(self.messageLabel)
            contentView.addSubview(self.progressIndicator)
            contentView.addSubview(button)

            self.configureIndeterminate()

            NSLayoutConstraint.activate([
                self.messageLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
                self.messageLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                self.messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

                self.progressIndicator.topAnchor.constraint(equalTo: self.messageLabel.bottomAnchor, constant: 16),
                self.progressIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

                button.topAnchor.constraint(equalTo: self.progressIndicator.bottomAnchor, constant: 24),
                button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor)
            ])

            panel.makeKeyAndOrderFront(nil)
            panel.makeMain()
            panel.becomeKey()
            panel.becomeMain()
            panel.orderFrontRegardless()
            panel.makeFirstResponder(button)
            self.window = panel
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    func updateMessage(_ text: String) {
        DispatchQueue.main.async {
            self.messageLabel.stringValue = text
        }
    }

    func configureDeterminate(totalSeconds: Double) {
        DispatchQueue.main.async {
            self.totalSeconds = totalSeconds
            self.progressIndicator.isIndeterminate = false
            self.progressIndicator.minValue = 0
            self.progressIndicator.maxValue = totalSeconds
            self.progressIndicator.doubleValue = 0
            self.progressIndicator.stopAnimation(nil)
        }
    }

    func updateProgress(elapsedSeconds: Double) {
        DispatchQueue.main.async {
            guard let total = self.totalSeconds else { return }
            let clamped = min(max(elapsedSeconds, 0), total)
            self.progressIndicator.doubleValue = clamped
        }
    }

    func configureIndeterminate() {
        DispatchQueue.main.async {
            self.totalSeconds = nil
            self.progressIndicator.isIndeterminate = true
            self.progressIndicator.startAnimation(nil)
        }
    }

    func close() {
        let work = {
            if let window = self.window {
                self.progressIndicator.stopAnimation(nil)
                window.close()
                self.window = nil
            }
            let app = NSApplication.shared
            if let policy = self.originalPolicy {
                app.setActivationPolicy(policy)
            } else {
                app.setActivationPolicy(.accessory)
            }
            self.originalPolicy = nil
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    @objc private func didPressCancel() {
        cancelButton?.isEnabled = false
        cancelHandler?()
    }
}
