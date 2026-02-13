//
//  UI.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/19/25.
//


// =============================
// File: UI_PresetsDroplets.swift - Presets and Droplets Panel
// =============================

import SwiftUI
import AppKit

struct UI_PresetsDroplets: View {
    @EnvironmentObject var state: AppState
    
    @State private var showSavePresetDialog = false
    @State private var newPresetName = ""
    // @State private var isExpanded = true

    private enum C {
        static let pickerWidth: CGFloat = 200
        static let panelInsets = EdgeInsets(top: 6, leading: 12, bottom: 2, trailing: 6)
        static let sectionSpacing: CGFloat = 12
    }

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.presetsExpanded) {
                VStack(alignment: .leading, spacing: C.sectionSpacing) {

                    // Current Preset Selection
                    HStack(spacing: 12) {
                        Text("Load Preset:").font(.headline)
                        
                        Picker("", selection: $state.settings.selectedPresetName) {
                            ForEach(state.availablePresets, id: \.name) { preset in
                                Text(preset.name).tag(preset.name)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: C.pickerWidth, alignment: .leading)
                        .onChange(of: state.settings.selectedPresetName) { newValue in
                            state.applyPreset(name: newValue)
                        }
                        .help("Apply saved preset to all panels")
                        
                        Spacer()
                    }

                    // Preset Actions
                    HStack(spacing: 12) {
                        Button("Save Current Settings...") {
                            newPresetName = ""
                            showSavePresetDialog = true
                        }
                        .help("Save current panel settings as a new preset")
                        
                        Button("Export as Droplet...") {
                            state.exportDroplet(name: state.settings.selectedPresetName)
                        }
                        .help("Export current preset as a drag-and-drop processing file")
                        
                        Button("Manage Presets...") {
                            state.showPreferences = true
                            // Note: Preferences will open to Presets tab
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
                .padding(.top, C.panelInsets.top)
            } label: {
                Text("Presets")
                    .font(.headline)
                    .opacity(1.0) // Always active since presets are always useful
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
                        // Show error alert
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
