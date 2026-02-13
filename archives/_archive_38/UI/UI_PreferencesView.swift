// =============================
// File: UI_PreferencesView.swift - Updated with Preset Management
// =============================
import SwiftUI
import AppKit

struct UI_PreferencesView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header (title only)
            HStack {
                Text("Preferences")
                    .font(.title3).bold()
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Content
            TabView {
                GeneralPrefs()
                    .environmentObject(state)
                    .tabItem { Label("General", systemImage: "slider.horizontal.3") }

                PresetManagementTab()
                    .environmentObject(state)
                    .tabItem { Label("Presets", systemImage: "doc.on.doc") }

                DeadlinePrefs()
                    .environmentObject(state)
                    .tabItem { Label("Deadline", systemImage: "network") }
            }
            .padding(16)

            Divider()

            // Footer with Done on lower-right
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)                // Esc
                    .keyboardShortcut("w", modifiers: .command)     // ⌘W
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 600, minHeight: 480)
    }
}

// MARK: - General

private struct GeneralPrefs: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Filename Order").font(.headline)
                Spacer()
                Button("Reset to Default") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        state.settings.filenameOrder = [.nclc, .scale, .compression]
                    }
                }
            }

            // Reorder list (Up/Down buttons; animate swaps)
            VStack(spacing: 6) {
                ForEach(Array(state.settings.filenameOrder.enumerated()), id: \.element.id) { idx, part in
                    HStack {
                        Image(systemName: "text.badge.star")
                            .foregroundColor(.secondary)
                            .opacity(0.6)
                        Text(part.label)
                        Spacer()
                        HStack(spacing: 6) {
                            Button {
                                move(idx, up: true)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(idx == 0)

                            Button {
                                move(idx, up: false)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(idx == state.settings.filenameOrder.count - 1)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
            }
            .animation(.easeInOut(duration: 0.18), value: state.settings.filenameOrder)
            .frame(height: 140)

            // Generic, order-driven preview (unrelated to current settings)
            VStack(alignment: .leading, spacing: 6) {
                Text("Preview").font(.headline)
                Text(sampleName(for: state.settings.filenameOrder))
                    .font(.body.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
    }

    private func move(_ index: Int, up: Bool) {
        var order = state.settings.filenameOrder
        guard order.indices.contains(index) else { return }
        let newIndex = up ? max(0, index - 1) : min(order.count - 1, index + 1)
        guard newIndex != index else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            order.swapAt(index, newIndex)
            state.settings.filenameOrder = order
        }
    }

    // Generic fragments that always exist, in any order:
    // Compression → "-HEVC", NCLC → "-sRGB", Scale → "-HALF"
    private func sampleFragment(for part: FilenamePart) -> String {
        switch part {
        case .compression: return "-HEVC"
        case .nclc:        return "-sRGB"
        case .scale:       return "-HALF"
        }
    }

    private func sampleName(for order: [FilenamePart]) -> String {
        let suffix = order.map(sampleFragment).joined()
        return "myFile\(suffix).mov"
    }
}

// MARK: - Preset Management Tab

private struct PresetManagementTab: View {
    @EnvironmentObject var state: AppState
    @State private var selectedPreset: EncodingPreset?
    @State private var showDeleteAlert = false
    @State private var showRenameDialog = false
    @State private var showResetAlert = false
    @State private var showExportSuccess = false
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Encoding Presets").font(.headline)
                Spacer()
                Button("Refresh") {
                    state.loadPresets()
                }
                .help("Reload presets from disk")
                
                Button("Reset to Default") {
                    showResetAlert = true
                }
                .help("Clear all presets and restore factory defaults")
            }

            HSplitView {
                // Left: Preset List
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Presets").font(.subheadline).foregroundColor(.secondary)
                    
                    List(state.availablePresets, id: \.id, selection: $selectedPreset) { preset in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(preset.name)
                                    .font(.callout)
                                    .fontWeight(preset.name == state.settings.selectedPresetName ? .semibold : .regular)
                                Spacer()
                                if preset.name == state.settings.selectedPresetName {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                        .font(.caption)
                                }
                            }
                            Text("Modified: \(DateFormatter.shortDateTime.string(from: preset.modifiedDate))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(preset)
                    }
                    .frame(minHeight: 200)
                }
                .frame(minWidth: 200)

                // Right: Preset Details & Actions
                VStack(alignment: .leading, spacing: 12) {
                    if let preset = selectedPreset {
                        Text("Preset Details").font(.subheadline).foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Name:")
                                Text(preset.name).fontWeight(.medium)
                                Spacer()
                            }
                            
                            HStack {
                                Text("Created:")
                                Text(DateFormatter.shortDateTime.string(from: preset.createdDate))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            
                            HStack {
                                Text("Modified:")
                                Text(DateFormatter.shortDateTime.string(from: preset.modifiedDate))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        .padding()
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                        
                        // Preview of key settings
                        Text("Settings Preview").font(.subheadline).foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Mode: \(preset.settings.runMode.rawValue)")
                            Text("• Quality: CRF \(preset.settings.qualityCRF)")
                            Text("• Scale: \(preset.settings.scale.rawValue)")
                            Text("• NCLC: \(preset.settings.nclcTag)")
                            Text("• Overlays: \(overlaysSummary(preset.settings))")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                        
                        Spacer()
                        
                        // Action Buttons
                        VStack(spacing: 8) {
                            Button("Apply Preset") {
                                state.applyPreset(name: preset.name)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(preset.name == state.settings.selectedPresetName)
                            
                            HStack(spacing: 8) {
                                Button("Export Droplet...") {
                                    state.exportDroplet(name: preset.name)
                                }
                                
                                Button("Rename...") {
                                    renameText = preset.name
                                    showRenameDialog = true
                                }
                                .disabled(preset.name == "Good Quality (Local)")
                            }
                            
                            Button("Delete") {
                                showDeleteAlert = true
                            }
                            .foregroundColor(.red)
                            .disabled(preset.name == "Good Quality (Local)")
                        }
                    } else {
                        Text("Select a preset to view details")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 300)
            }
            .frame(minHeight: 300)
        }
        .alert("Delete Preset", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let preset = selectedPreset {
                    do {
                        try state.deletePreset(name: preset.name)
                        selectedPreset = nil
                    } catch {
                        // Show error
                    }
                }
            }
        } message: {
            if let preset = selectedPreset {
                Text("Are you sure you want to delete the preset '\(preset.name)'? This cannot be undone.")
            }
        }
        .alert("Reset to Factory Defaults", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset All Presets", role: .destructive) {
                do {
                    try PresetManager.shared.resetToDefaults()
                    state.loadPresets()
                    selectedPreset = nil
                    // Reset to Default preset
                    state.settings.selectedPresetName = "Good Quality (Local)"
                    state.applyPreset(name: "Good Quality (Local)")
                } catch {
                    // Show error
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Reset Failed"
                        alert.informativeText = "Could not reset presets: \(error.localizedDescription)"
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        } message: {
            Text("This will delete all your custom presets and restore the factory default presets. This action cannot be undone.\n\nAre you sure you want to continue?")
        }
        .alert("Rename Preset", isPresented: $showRenameDialog) {
            TextField("New Name", text: $renameText)
            Button("Cancel", role: .cancel) {
                renameText = ""
            }
            Button("Rename") {
                if let preset = selectedPreset {
                    do {
                        try PresetManager.shared.renamePreset(oldName: preset.name, newName: renameText)
                        state.loadPresets()
                        // Update selection to renamed preset
                        selectedPreset = state.availablePresets.first { $0.name == renameText }
                    } catch {
                        // Show error
                    }
                }
                renameText = ""
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a new name for this preset:")
        }
    }
    
    private func overlaysSummary(_ settings: Settings) -> String {
        var overlays: [String] = []
        if settings.burnInTimecode { overlays.append("TC") }
        if settings.burnInFrames { overlays.append("Frames") }
        if settings.burnInFilename { overlays.append("Filename") }
        return overlays.isEmpty ? "None" : overlays.joined(separator: ", ")
    }
}

// MARK: - Deadline

private struct DeadlinePrefs: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Deadline Command").font(.headline)

            HStack(spacing: 8) {
                TextField("Auto-detect", text: Binding(
                    get: { state.settings.deadlineCommandPath },
                    set: { state.settings.deadlineCommandPath = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

                Button("Browse…") { pickDeadlineCmd() }
                Button("Reset to Auto") { state.settings.deadlineCommandPath = "" }
            }

            Text("If empty, Mr HEVC will auto-detect Deadline's command-line tool.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private func pickDeadlineCmd() {
        let panel = NSOpenPanel()
        panel.title = "Locate Deadline Command"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["", "command", "sh", "bin", ""]
        if panel.runModal() == .OK, let url = panel.url {
            state.settings.deadlineCommandPath = url.path
        }
    }
}

// MARK: - DateFormatter Extension
extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
