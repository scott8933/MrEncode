//
//  KeyEventCatcher.swift
//  MrEncode
//
//  Created by scott ulrich on 1/23/26.
//

import SwiftUI

#if os(macOS)
import AppKit

struct KeyEventCatcher: NSViewRepresentable {
    /// Return true to consume the event; false to pass through.
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let v = KeyCatcherView()
        v.onKeyDown = onKeyDown
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyCatcherView)?.onKeyDown = onKeyDown
        // IMPORTANT: no makeFirstResponder here
    }

    private final class KeyCatcherView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Claim responder once when the view first attaches to a window.
            // Do NOT keep re-claiming it on updates.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // If a text field is already editing, don't steal focus.
                if let fr = self.window?.firstResponder, fr is NSTextView { return }
                self.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            // If the user is editing text, do not intercept keystrokes.
            if let fr = window?.firstResponder, fr is NSTextView {
                super.keyDown(with: event)
                return
            }

            if onKeyDown?(event) == true {
                return // consumed
            }

            super.keyDown(with: event)
        }
    }
}
#endif
