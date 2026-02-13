// =============================
// File: UI_PreferencesView.swift
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
        .frame(minWidth: 520, minHeight: 360)
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

            Text("If empty, Mr HEVC will auto-detect Deadline’s command-line tool.")
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
