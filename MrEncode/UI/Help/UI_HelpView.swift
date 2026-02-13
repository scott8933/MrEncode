//
//  UI_HelpView.swift
//  MrEncode
//
//  Created by scott ulrich on 1/29/26.
//

// UI_HelpView.swift
// MrEncode

import SwiftUI

struct UI_HelpView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var router = HelpRouting.shared

    @State private var searchText: String = ""
    @State private var selection: HelpRouting.TopicID? = .gettingStarted

    private var topics: [HelpTopic] { HelpTopics.all }

    private var filteredTopics: [HelpTopic] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return topics }

        let needle = q.lowercased()
        return topics.filter { t in
            t.title.lowercased().contains(needle)
            || t.summary.lowercased().contains(needle)
            || t.body.contains(where: { block in
                switch block {
                case .heading(let s):
                    return s.lowercased().contains(needle)
                case .paragraph(let s):
                    return s.lowercased().contains(needle)
                case .bulleted(let items):
                    return items.contains(where: { $0.lowercased().contains(needle) })
                case .shortcuts(let rows):
                    return rows.contains(where: { row in
                        row.action.lowercased().contains(needle) || row.keys.lowercased().contains(needle)
                    })
                }
            })
        }
    }

    private var selectedTopic: HelpTopic {
        topics.first(where: { $0.id == selection }) ?? topics[0]
    }

    var body: some View {
        NavigationSplitView {
            List(filteredTopics, selection: $selection) { topic in
                VStack(alignment: .leading, spacing: 4) {
                    Text(topic.title)
                        .font(.headline)
                    Text(topic.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Help")
            .searchable(text: $searchText, placement: .sidebar)
            .onAppear {
                // Handle menu-triggered topic jump.
                if let t = router.requestedTopic {
                    selection = t
                    router.requestedTopic = nil
                }
            }
            .onChange(of: router.requestedTopic) { newValue in
                // macOS 12/13-compatible overload
                guard let t = newValue else { return }
                selection = t
                router.requestedTopic = nil
            }
        } detail: {
            ScrollView {
                HelpTopicView(topic: selectedTopic)
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.top, 4)
            }
            .navigationTitle(selectedTopic.title)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(topic.body.enumerated()), id: \.offset) { _, block in
                switch block {

                case .heading(let s):
                    Text(s)
                        .font(.title3)
                        .bold()

                case .paragraph(let s):
                    Text(s)
                        .font(.body)
                        .textSelection(.enabled)

                case .bulleted(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•")
                                Text(item)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .font(.body)

                case .shortcuts(let rows):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(row.action)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(row.keys)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Divider().opacity(0.25)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Default Topics

private enum HelpTopics {
    static let all: [HelpTopic] = [
        HelpTopic(
            id: .gettingStarted,
            title: "Getting Started",
            summary: "Drop media, choose options, encode.",
            body: [
                .paragraph("MrEncode encodes video media to your chosen compression settings. Most of the time, the workflow is: drop media into the Drop Zone, confirm Compression / Scale & Crop / NCLC / Overlay Shot Info, then press Start."),
                .heading("Auto-Encode vs Manual"),
                .bulleted([
                    "Manual: you decide what to encode (checked rows) and when to press Start.",
                    "Auto-Encode: dropping new media will submit automatically when queued."
                ])
            ]
        ),
        HelpTopic(
            id: .importing,
            title: "Importing Media",
            summary: "Drop, Command–I, or double-click in the queue.",
            body: [
                .paragraph("You can add media in multiple ways:"),
                .bulleted([
                    "Drag-and-drop into the Drop Zone.",
                    "Choose File ▸ Import Media… (Command–I).",
                    "Double-click in the queue area to open the import dialog (if enabled in your build)."
                ]),
                .paragraph("Imported media appears as queued rows. In Manual mode, check the rows you want to encode and press Start.")
            ]
        ),
        HelpTopic(
            id: .queue,
            title: "Queue",
            summary: "Select rows, duplicate, and manage encode order.",
            body: [
                .paragraph("The queue is an ordered list of media to encode. Each row tracks status (queued, processing, done, blocked) and whether it is checked for encoding."),
                .heading("Selection"),
                .bulleted([
                    "Click a row to select it.",
                    "Use Duplicate (Command–D) to create a second row for the same source, typically with different settings."
                ])
            ]
        ),
        HelpTopic(
            id: .keyboardShortcuts,
            title: "Keyboard Shortcuts",
            summary: "Common shortcuts available in MrEncode.",
            body: [
                .heading("File"),
                .shortcuts([
                    HelpShortcutRow(action: "Import Media…", keys: "⌘I"),
                    HelpShortcutRow(action: "Save Queue…", keys: "⇧⌘S"),
                    HelpShortcutRow(action: "Open Queue…", keys: "⌘O"),
                    HelpShortcutRow(action: "Append Queue…", keys: "⌥⌘O")
                ]),
                .heading("Edit"),
                .shortcuts([
                    HelpShortcutRow(action: "Duplicate", keys: "⌘D")
                ]),
                .paragraph("Tip: You can also import by drag-and-drop into the Drop Zone. Some builds also support double-clicking in the queue area to import.")
            ]
        ),
        HelpTopic(
            id: .droplets,
            title: "Droplets",
            summary: "Export presets as droplets for one-click encoding.",
            body: [
                .paragraph("Droplets are small apps that launch MrEncode with a preset and accept dropped media. Use Presets ▸ Export Droplet to create one."),
                .bulleted([
                    "Droplets can be configured to exit when finished.",
                    "Droplets can carry extra runtime arguments (if enabled in your build)."
                ])
            ]
        ),
        HelpTopic(
            id: .renderfarm,
            title: "Renderfarm",
            summary: "Optional: submit encodes to Deadline (if installed).",
            body: [
                .paragraph("If Deadline is detected, MrEncode can submit jobs to the renderfarm. If Deadline is not installed, Renderfarm options may be hidden or disabled."),
                .bulleted([
                    "Local encoding uses your current machine.",
                    "Renderfarm encoding submits jobs and monitors status."
                ])
            ]
        ),
        HelpTopic(
            id: .troubleshooting,
            title: "Troubleshooting",
            summary: "Common issues and where to look.",
            body: [
                .heading("Blocked rows"),
                .bulleted([
                    "If a source is missing or inaccessible, the row may show Blocked.",
                    "Check network mounts and permissions, then re-add the media."
                ]),
                .heading("Logs"),
                .bulleted([
                    "Use the Log window to view details about encoding and submission.",
                    "If you report an issue, include a log excerpt around the failure."
                ])
            ]
        )
    ]
}
