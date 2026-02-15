//
//  UI_PresetsDroplets.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/16/25.
//



//
// MARK: - UI_PresetsDroplets.swift (Revised w/ “Import Droplet…”)
//

import SwiftUI
import AppKit

struct UI_PresetsDroplets: View {
    @EnvironmentObject var state: AppState
    
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }
    
    @StateObject private var presetViewModel = PresetViewModel()
    
    @State private var loadedPresetName: String? = nil
    @State private var loadedPresetBaseline: Settings? = nil
    @State private var showSavePresetDialog = false
    @State private var newPresetName = ""
    @State private var hovering = false
    
    @Binding var isExpanded: Bool
    
    private var presetTitleName: String {
        loadedPresetName ?? (state.settings.selectedPresetName.isEmpty ? "Choose…" : state.settings.selectedPresetName)
    }

    // Shows "(Modified)" when current settings differ from the loaded baseline
    private var presetIsModified: Bool {
        guard let baseline = loadedPresetBaseline else { return false }
        return contentDiffers(from: baseline, to: state.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // HEADER (clickable)
            Button {
                withAnimation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: StyleConstants.Spacing.headerSpacing) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(C.textSecondary)
                        .frame(width: 14, height: 14)

                    // Keep your menu exactly as-is
                    Menu {
                        ForEach(state.availablePresets) { preset in
                            Button(preset.name) {
                                let wasExpanded = state.settings.presetsExpanded
                                state.settings.selectedPresetName = preset.name
                                state.applyPreset(name: preset.name)
                                state.settings.presetsExpanded = wasExpanded

                                loadedPresetName = preset.name
                                loadedPresetBaseline = state.settings
                            }
                        }
                        Divider()
                        Button("Import Droplet…") { importDropletPreset() }
                    } label: {
                        HStack(spacing: 6) {
                            if isExpanded {
                                Text("Presets:")
                                    .font(.headline)
                                    .foregroundColor(hovering ? .accentColor : .primary)
                            }

                            (
                                Text(presetTitleName)
                                    .foregroundColor(hovering ? C.presetTitleHover : C.textPrimary)
                                +
                                (presetIsModified
                                    ? Text(" (Modified)")
                                        .foregroundColor(hovering ? C.presetTitleHover : C.modifiedAccent)
                                    : Text(""))
                            )
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        }
                        .contentShape(Rectangle())
                        .onHover { hovering = $0 }
                        .animation(.easeInOut(duration: StyleConstants.Motion.hoverAnimationDuration), value: hovering)
                    }
                    .buttonStyle(.plain)
                    .help("Choose a preset")

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // CONTENT (conditionally inserted => animates reliably)
            if isExpanded {
                VStack(alignment: .leading, spacing: StyleConstants.Spacing.sectionSpacing) {
                    PresetActions()
                        .environmentObject(presetViewModel)
                }
                .padding(StyleConstants.panelInsets)
                .padding(.top, StyleConstants.panelInsets.top)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration), value: isExpanded)
        .onAppear {
            guard loadedPresetBaseline == nil else { return }
            let currentName = state.settings.selectedPresetName
            guard !currentName.isEmpty else { return }
            loadedPresetName = currentName
            loadedPresetBaseline = presetBaseline(for: currentName)
        }
        .onChange(of: state.settings.selectedPresetName) { newName in
            guard !newName.isEmpty else { return }
            loadedPresetName = newName
            loadedPresetBaseline = presetBaseline(for: newName)
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

    // All button layout tuning in one place
    private enum M {
        static let hSpacing: CGFloat = 14          // spacing between buttons in the row
        static let buttonWidth: CGFloat = 108
        static let buttonHeight: CGFloat = 24      // overall control height
        static let labelHPad: CGFloat = 8          // inner horizontal padding
        static let labelVPad: CGFloat = 0          // inner vertical padding (usually 0 if you set buttonHeight)
        static let font: Font = .caption
        static let controlSize: ControlSize = .small
    }

    var body: some View {
        HStack(spacing: M.hSpacing) {
            presetActionButton("Save Preset", help: "Save current panel settings as a new preset") {
                showSaveDialog = true
            }

            presetActionButton("Export Droplet", help: "Export current preset as a drag-and-drop processing file") {
                state.exportCurrentSettingsAsDroplet()
            }

            presetActionButton("Import Droplet", help: "Import a MrEncode droplet (.app) or preset JSON into your saved presets") {
                importPresetFromDroplet()
            }

            presetActionButton("Manage Presets", help: "Rename, delete, and organize presets") {
                state.showPreferences = true
            }

            Spacer()
        }
        .controlSize(M.controlSize)
        .buttonStyle(.bordered)
        .alert("Save Preset", isPresented: $showSaveDialog) {
            SavePresetAlert()
                .environmentObject(state)
                .environmentObject(presetViewModel)
        }
    }

    private func presetActionButton(
        _ title: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(M.font)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, M.labelHPad)
                .padding(.vertical, M.labelVPad)
        }
        .frame(width: M.buttonWidth, height: M.buttonHeight)
        .help(help)
    }

    // MARK: - Import handler

    private func importPresetFromDroplet() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedFileTypes = ["app", "json", "scpt"]
        panel.message = "Select a MrEncode droplet (.app) or a preset JSON to import."

        if panel.runModal() == .OK, let url = panel.url {
            do {
                // Load settings + a suggested name from the droplet/json
                let (settings, suggested) = try presetViewModel.importDroplet(from: url)

                // Ensure unique name against current list
                let finalName = uniquePresetName(basedOn: suggested)

                // Save and adopt
                try presetViewModel.savePreset(name: finalName, settings: settings)
                state.settings = settings
                state.settings.selectedPresetName = finalName
                // Parent view’s .onChange(of: selectedPresetName) will refresh the (Modified) baseline

                // Feedback
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Imported droplet as preset"
                    alert.informativeText = "“\(finalName)”"
                    alert.alertStyle = .informational
                    alert.runModal()
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Import Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    private func uniquePresetName(basedOn base: String) -> String {
        let existing = Set(state.availablePresets.map { $0.name })
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}



private struct PresetInfo: View {
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("• **Presets** save all panel settings for quick switching")
            Text("• **Droplets** are exported preset files that auto-process videos when dropped")
            Text("• Drag video files onto a .mrencode droplet file to process with those settings")
        }
        .font(.caption)
        .foregroundColor(C.textSecondary)
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

    // NEW: Import handler + helpers

    /// Opens a panel to import a droplet (.app), preset .json, or AppleScript .scpt into saved presets.
    private func importDropletPreset() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedFileTypes = ["app", "json", "scpt"]
        panel.message = "Select a MrEncode droplet (.app) or a preset JSON to import."
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let (settings, suggested) = try presetViewModel.importDroplet(from: url)
                let finalName = uniquePresetName(basedOn: suggested)

                // Save to presets and adopt as current
                try presetViewModel.savePreset(name: finalName, settings: settings)
                state.settings = settings
                state.settings.selectedPresetName = finalName

                // Reset the (Modified) baseline for header
                loadedPresetName = finalName
                loadedPresetBaseline = settings

                // Feedback
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Imported droplet as preset"
                    alert.informativeText = "“\(finalName)”"
                    alert.alertStyle = .informational
                    alert.runModal()
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Import Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    /// Ensures a unique preset name by appending " 2", " 3", …
    private func uniquePresetName(basedOn base: String) -> String {
        let existing = Set(state.availablePresets.map { $0.name })
        if !existing.contains(base) { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func presetBaseline(for presetName: String) -> Settings? {
        guard let preset = state.availablePresets.first(where: { $0.name == presetName }) else {
            return nil
        }

        var baseline = state.settings
        baseline.applyPreset(preset.settings, presetName: presetName)
        return baseline
    }
}

// MARK: - Helpers

/// Returns true if user-changed *content* differs from the loaded preset baseline.
/// Ignores panel/chevron expansion states, selectedPresetName, etc.
private func contentDiffers(from baseline: Settings, to current: Settings) -> Bool {
    // Compare only meaningful encoding options (expand/chevron states are intentionally ignored)
    if baseline.runMode != current.runMode { return true }
    if baseline.codec != current.codec { return true }
    if baseline.qualityCRF != current.qualityCRF { return true }
    if baseline.containerFormat != current.containerFormat { return true }
    if baseline.outputSuffix != current.outputSuffix { return true }
    if baseline.scale != current.scale { return true }
    if baseline.burnInFrames != current.burnInFrames { return true }
    if baseline.burnInTimecode != current.burnInTimecode { return true }
    if baseline.burnInFilename != current.burnInFilename { return true }

    // Add other *content* fields here as needed, but DO NOT include UI-only flags like:
    // - generalExpanded, presetsExpanded, message panel states, etc.
    // - selectedPresetName

    return false
}
