//
//  FloatingGeometryPrefs.swift
//  MrEncode
//
//  Created by scott ulrich on 2/16/26.
//


import SwiftUI

// Shared coordinate space name
enum FloatingC {
    static let coordSpaceName = "ContentCS"
}

// MARK: - Preference Keys

struct DropZoneFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct FooterFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct FloatingControlsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Reporter modifiers

struct OptionsBottomPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>?
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue()
    }
}

struct DropZoneTopYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0  // Changed from .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension Notification.Name {
    static let dropZoneFrameChanged = Notification.Name("dropZoneFrameChanged")
    static let footerFrameChanged = Notification.Name("footerFrameChanged")  // Add this
}

extension View {

    /// Attach this to the Drop Zone root view (in UI_Queue)
    func reportDropZoneFrame() -> some View {
        self.overlay {
            GeometryReader { geo in
                Color.clear.preference(
                    key: DropZoneFramePreferenceKey.self,
                    value: geo.frame(in: .named(FloatingC.coordSpaceName))
                )
            }
        }
    }

    /// Attach this to FooterOverlay root view
    func reportFooterFrame() -> some View {
        self.overlay {
            GeometryReader { geo in
                Color.clear.preference(
                    key: FooterFramePreferenceKey.self,
                    value: geo.frame(in: .named(FloatingC.coordSpaceName))
                )
            }
        }
    }
}
