//
//  UI_PresetsDroplets.swift
//  MrHEVC
//
//  Split-header: Chevron + Title-as-Menu
//  - Collapsed: show only current preset name (full opacity)
//  - Expanded:  show "Presets: " + current preset name
//

import SwiftUI
import AppKit

struct UI_PresetsDroplets: View {
    @EnvironmentObject var state: AppState

    @State private var showSavePresetDialog = false
    @State private var newPresetName = ""

    private enum C {
        static let panelInsets = EdgeInsets(top: 6, leading: 12, bottom: 2, trailing: 6)
        static let sectionSpacing: CGFloat = 12
        static let headerSpacing: CGFloat = 8
    }

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.presetsExpanded) {
                // CONTENT
                VStack(alignment: .leading, spacing: C.sectionSpacing) {

                    // Preset Actions
                    HStack(spacing: 12) {
                        Button("Save Current Settings…") {
                            newPresetName = ""
                            showSavePresetDialog = true
                        }
                        .help("Save current panel settings as a new preset")

                        Button("Export as Droplet…") {
                            state.exportDroplet(name: state.settings.selectedPresetName)
                        }
                        .help("Export current preset as a drag-and-drop processing file")

                        Button("Manage Presets…") {
                            state.showPreferences = true
                        }
                        .help("Rename, delete, and organize presets")

                        Spacer()
                    }
                    .buttonStyle(.bordered)

                    // Info text
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• **Presets** save all panel settings for quick switching")
                        Text("• **Droplets** are exported preset files that auto-process videos when dropped")
                        Text("• Drag .mov files onto a .mrhevc droplet file to process with those settings")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }
                .padding(C.panelInsets)
                // Double header-to-content top padding (base + extra)
                .padding(.top, C.panelInsets.top)
            } label: {
                // LABEL (header row): Chevron (from DisclosureGroup) + Title-as-Menu
                let isExpanded = state.settings.presetsExpanded

                HStack(spacing: C.headerSpacing) {
                    // The menu replaces the static "Presets" text and the old "Load Preset" row.
                    Menu {
                        ForEach(state.availablePresets, id: \.name) { preset in
                            Button(preset.name) {
                                let wasExpanded = state.settings.presetsExpanded   // preserve current reveal state
                                state.settings.selectedPresetName = preset.name
                                state.applyPreset(name: preset.name)
                                state.settings.presetsExpanded = wasExpanded       // restore it (no auto-reveal)
                            }
                        }
                    } label: {
                        // Expanded:   "Presets: <CurrentName> ▾"
                        // Collapsed:  "<CurrentName> ▾"
                        HStack(spacing: 6) {
                            if isExpanded {
                                // Prefix only when revealed
                                Text("Presets:")
                                    .font(.headline)
                                    .opacity(1.0)  // full when revealed
                                    .accessibilityHidden(true)
                            }

                            // Current selection — always full opacity
                            Text(state.settings.selectedPresetName.isEmpty ? "Choose…" : state.settings.selectedPresetName)
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .opacity(1.0)  // keep full even when collapsed

                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .accessibilityHidden(true)
                                // Subtle dim when collapsed, but keep the name full
                                .opacity(isExpanded ? 1.0 : 0.35)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Choose a preset")
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Presets")
                    .accessibilityValue(state.settings.selectedPresetName.isEmpty ? "None" : state.settings.selectedPresetName)

                    Spacer()
                }
                // Respect the 12pt leading inset visually for the header row
                //.padding(.leading, C.panelInsets.leading)
            }
        }
        .alert("Save Preset", isPresented: $showSavePresetDialog) {
            TextField("Preset Name", text: $newPresetName)
            Button("Cancel", role: .cancel) {
                newPresetName = ""
            }
            Button("Save") {
                let trimmed = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    do {
                        try state.saveCurrentAsPreset(name: trimmed)
                    } catch {
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.messageText = "Save Failed"
                            alert.informativeText = error.localizedDescription
                            alert.alertStyle = .warning
                            alert.runModal()
                        }
                    }
                }
                newPresetName = ""
            }
            .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for the current settings:")
        }
    }
}
