//
//  HelpSystem.swift
//  MrEncode
//
//  Created by scott ulrich on 1/29/26.
//


// HelpSystem.swift
// MrEncode

import SwiftUI

// MARK: - Routing

/// Tiny shared router so Commands can request a specific help topic.
/// This avoids duplicating windows and keeps menu items simple.
final class HelpRouting: ObservableObject {
    static let shared = HelpRouting()
    private init() {}

    enum TopicID: String, CaseIterable, Identifiable {
        case gettingStarted
        case importing
        case queue
        case keyboardShortcuts
        case droplets
        case renderfarm
        case troubleshooting

        var id: String { rawValue }
    }

    @Published var requestedTopic: TopicID? = nil
}

// MARK: - Content Model

struct HelpTopic: Identifiable, Hashable {
    let id: HelpRouting.TopicID
    let title: String
    let summary: String
    let body: [HelpBlock]
}

struct HelpShortcutRow: Identifiable, Hashable {
    // Stable id (no UUID churn)
    var id: String { "\(action)|\(keys)" }
    let action: String
    let keys: String
}

enum HelpBlock: Hashable {
    case heading(String)
    case paragraph(String)
    case bulleted([String])
    case shortcuts([HelpShortcutRow])
}
