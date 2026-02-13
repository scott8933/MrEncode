// =============================
// File: UI_PreferencesView.swift - Updated with Preset Management
// =============================


//
// This UI looks pretty terrible
// TODO need to clean up and conform to StyleContents
// >>> fixed 01-28-26 <<<

// TODO still need to make the Presets tab look a little better


import SwiftUI
import AppKit
import Foundation

struct UI_PreferencesView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let showRenderfarmTab =
            state.settings.runMode == .remoteDeadline
            || state.deadlineAvailable
            || state.isRefreshingDeadline
            || state.settings.lastDeadlineFetch != nil
        
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
                ScrollView(.vertical) {
                    GeneralPrefs()
                        .environmentObject(state)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }

                ScrollView(.vertical) {
                    PresetManagementTab()
                        .environmentObject(state)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .tabItem { Label("Presets", systemImage: "doc.on.doc") }

                if showRenderfarmTab {
                    ScrollView(.vertical) {
                        DeadlinePrefs()
                            .environmentObject(state)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .tabItem { Label("Renderfarm", systemImage: "network") }
                }
            }

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
    @State private var showRestoreDefaults = false
    @State private var hoverResetOrder = false
    
    private let labelWidth: CGFloat = 120
    private let itemGap: CGFloat = 10

    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 6) {
                Text("Filename Order").font(.headline)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        state.settings.filenameOrder = [.nclc, .scale, .compression]
                    }
                } label: {
                    Text("Reset to Default")
                        .foregroundColor(hoverResetOrder ? .accentColor : .secondary)
                        .underline(hoverResetOrder)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    hoverResetOrder = inside
                    inside ? NSCursor.pointingHand.push() : NSCursor.pop()
                }
                .help("Restore the default filename component order")


                Spacer(minLength: 0)
            }

            // Reorder list (Up/Down buttons; animate swaps)
            VStack(spacing: 4) {
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
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
            }
            .animation(.easeInOut(duration: 0.18), value: state.settings.filenameOrder)
            //.frame(height: 140)

            Grid(alignment: .leading, horizontalSpacing: itemGap, verticalSpacing: 10) {

                GridRow(alignment: .top) {
                    Text("Suffix Separator")
                        .font(.headline)
                        .frame(width: labelWidth, alignment: .leading)

                    TextField("-", text: Binding(
                        get: { state.settings.suffixSeparator },
                        set: { state.settings.suffixSeparator = sanitizeSuffixSeparator($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80, alignment: .leading)
                    .help("Used only for auto-suggested suffixes. Manual suffix text is always literal.")
                }

                GridRow(alignment: .top) {
                    Text("Preview")
                        .font(.headline)
                        .frame(width: labelWidth, alignment: .leading)

                    Text(sampleName(for: state.settings.filenameOrder))
                        .font(.body.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            
            Divider()
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Done Chime Volume")
                    .font(.headline)

                GeometryReader { geo in
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { state.settings.doneChimeVolume },
                                set: { state.settings.doneChimeVolume = $0 }
                            ),
                            in: 0.0...1.0,
                            step: 0.01
                        )
                        .frame(width: geo.size.width * 0.75)

                        Button {
                            Task { @MainActor in
                                SoundManager.shared.playDoneChime()
                            }
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .imageScale(.small)
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.secondary.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Play test chime")

                    }
                }
                .frame(height: 22)
            }


            Divider()
                .padding(.vertical, 8)

            Button(role: .destructive) {
                showRestoreDefaults = true
            } label: {
                Label("Restore All Preferences…", systemImage: "arrow.counterclockwise.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red.opacity(0.75))
            .help("Replace your current preferences with the factory defaults bundled with MrEncode. Presets are unaffected.")
        }
        .alert("Restore Factory Preferences?", isPresented: $showRestoreDefaults) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                state.resetPreferencesToFactoryDefaults()
            }
        } message: {
            Text("This will replace all preferences with the factory defaults shipped in default_prefs.json. Custom presets are not changed.")
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

    // Generic fragments that always exist, in any order.
    // Use the current separator preference.
    private func sampleFragment(for part: FilenamePart) -> String {
        switch part {
        case .compression: return applySuggestedSeparator("HEVC", settings: state.settings)
        case .nclc:        return applySuggestedSeparator("sRGB", settings: state.settings)
        case .scale:       return applySuggestedSeparator("HALF", settings: state.settings)
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
                                .disabled(preset.name == "Good Quality - Local")
                            }
                            
                            Button("Delete") {
                                showDeleteAlert = true
                            }
                            .foregroundColor(.red)
                            .disabled(preset.name == "Good Quality - Local")
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
                    state.settings.selectedPresetName = "Good Quality - Local"
                    state.applyPreset(name: "Good Quality - Local")
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
