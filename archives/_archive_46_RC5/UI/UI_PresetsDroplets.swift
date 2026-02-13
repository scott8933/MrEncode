//
// MARK: - UI_PresetsDroplets.swift (Updated)
//

import SwiftUI
import AppKit

struct UI_PresetsDroplets: View {
    @EnvironmentObject var state: AppState
    @StateObject private var presetViewModel = PresetViewModel()
    
    @State private var showSavePresetDialog = false
    @State private var newPresetName = ""
    @State private var hovering = false

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.presetsExpanded) {
                VStack(alignment: .leading, spacing: StyleConstants.sectionSpacing) {
                    PresetActions()
                        .environmentObject(presetViewModel)
                    PresetInfo()
                }
                .padding(StyleConstants.panelInsets)
                .padding(.top, StyleConstants.panelInsets.top)
            } label: {
                HStack(spacing: StyleConstants.headerSpacing) {
                    Menu {
                        ForEach(state.availablePresets) { preset in
                            Button(preset.name) {
                                let wasExpanded = state.settings.presetsExpanded
                                state.settings.selectedPresetName = preset.name
                                state.applyPreset(name: preset.name)
                                state.settings.presetsExpanded = wasExpanded
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if state.settings.presetsExpanded {
                                Text("Presets:")
                                    .font(.headline)
                                    .opacity(1.0)
                                    .foregroundColor(hovering ? .accentColor : .primary)
                            }

                            Text(state.settings.selectedPresetName.isEmpty ? "Choose…" : state.settings.selectedPresetName)
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .opacity(1.0)
                                .foregroundColor(hovering ? .accentColor : .primary)
                        }
                        .contentShape(Rectangle())
                        .onHover { hovering = $0 }
                        .animation(.easeInOut(duration: 0.15), value: hovering)
                    }
                    .buttonStyle(.plain)
                    .help("Choose a preset")

                    Spacer()
                }
            }
        }
        .alert("Save Preset", isPresented: $showSavePresetDialog) {
            TextField("Preset Name", text: $newPresetName)
            Button("Cancel", role: .cancel) { newPresetName = "" }
            Button("Save") { savePreset() }
                .disabled(!presetViewModel.validatePresetName(newPresetName).valid)
        } message: {
            Text("Enter a name for the current settings:")
        }
    }
}

// MARK: - Subviews

private struct PresetHeader: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var presetViewModel: PresetViewModel
    
    private enum C {
        static let headerSpacing: CGFloat = 8
    }
    
    var body: some View {
        let isExpanded = state.settings.presetsExpanded

        HStack(spacing: C.headerSpacing) {
            // Preset Selection Menu
            Menu {
                ForEach(state.availablePresets, id: \.id) { preset in
                    Button(presetViewModel.presetDisplayName(
                        preset,
                        isCurrent: preset.name == state.settings.selectedPresetName
                    )) {
                        presetViewModel.applyPreset(preset)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    // Title text changes based on expanded state
                    Text(isExpanded ? "Presets:" : "")
                        .fontWeight(.medium)
                        .opacity(isExpanded ? 1.0 : 0.0)
                    
                    // Current preset name
                    Text(state.settings.selectedPresetName.isEmpty ?
                         "No Preset" : state.settings.selectedPresetName)
                        .fontWeight(isExpanded ? .regular : .medium)
                        .opacity(isExpanded ? 1.0 : 0.35)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose a preset")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Presets")
            .accessibilityValue(state.settings.selectedPresetName.isEmpty ?
                               "None" : state.settings.selectedPresetName)

            Spacer()
        }
    }
}

private struct PresetActions: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var presetViewModel: PresetViewModel
    @State private var showSaveDialog = false
    
    var body: some View {
        HStack(spacing: 12) {
            Button("Save Current Settings…") {
                showSaveDialog = true
            }
            .help("Save current panel settings as a new preset")

            Button("Export as Droplet…") {
                if let currentPreset = state.availablePresets.first(where: {
                    $0.name == state.settings.selectedPresetName
                }) {
                    presetViewModel.exportDroplet(currentPreset)
                } else {
                    state.exportDroplet(name: state.settings.selectedPresetName)
                }
            }
            .help("Export current preset as a drag-and-drop processing file")

            Button("Manage Presets…") {
                state.showPreferences = true
            }
            .help("Rename, delete, and organize presets")

            Spacer()
        }
        .buttonStyle(.bordered)
        .alert("Save Preset", isPresented: $showSaveDialog) {
            SavePresetAlert()
                .environmentObject(state)
                .environmentObject(presetViewModel)
        }
    }
}

private struct PresetInfo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("• **Presets** save all panel settings for quick switching")
            Text("• **Droplets** are exported preset files that auto-process videos when dropped")
            Text("• Drag .mov files onto a .mrhevc droplet file to process with those settings")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.top, 4)
    }
}

private struct SavePresetAlert: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var presetViewModel: PresetViewModel
    @State private var presetName = ""
    
    var body: some View {
        VStack {
            TextField("Preset Name", text: $presetName)
            
            HStack {
                Button("Cancel", role: .cancel) {
                    presetName = ""
                }
                
                Button("Save") {
                    savePreset()
                }
                .disabled(!presetViewModel.validatePresetName(presetName).valid)
            }
        }
    }
    
    private func savePreset() {
        let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let validation = presetViewModel.validatePresetName(trimmed)
        
        guard validation.valid else {
            showValidationError(validation.reason ?? "Invalid name")
            return
        }
        
        do {
            try presetViewModel.savePreset(name: trimmed, settings: state.settings)
            presetName = ""
        } catch {
            showSaveError(error)
        }
    }
    
    private func showValidationError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Invalid Preset Name"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
    
    private func showSaveError(_ error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Save Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

// MARK: - Extensions for UI_PresetsDroplets

extension UI_PresetsDroplets {
    private func savePreset() {
        let trimmed = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let validation = presetViewModel.validatePresetName(trimmed)
        
        guard validation.valid else {
            showValidationError(validation.reason ?? "Invalid name")
            return
        }
        
        do {
            try presetViewModel.savePreset(name: trimmed, settings: state.settings)
            newPresetName = ""
        } catch {
            showSaveError(error)
        }
    }
    
    private func showValidationError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Invalid Preset Name"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
    
    private func showSaveError(_ error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Save Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
