// =============================
// File: UI_HeaderBar.swift - Simple Header Bar
// =============================

// UI_HeaderBar.swift — use consolidated widths from AppColors

import SwiftUI

struct UI_HeaderBar: View {
    let title: String
    @Binding var runMode: RunMode
    @Binding var autoEncodeOnDrop: Bool

    /// Set true when this header sits above the Queue so we show "Clear All".
    var showsQueueActions: Bool = false

    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: StyleConstants.headerSpacing) {

            // Left cluster: title + optional queue actions
            HStack(spacing: StyleConstants.headerSpacing) {
                Text(title)
                    .font(.largeTitle)
                    .bold()

                if showsQueueActions {
                    Button("Clear All") {
                        state.clearAll()
                    }
                    // Compile-safe: disable when queue is empty.
                    // (If you later expose an "isEncoding" or "hasActiveJobs" flag,
                    // add it to this condition.)
                    .disabled(state.files.isEmpty)
                    .help("Remove all non-encoding items from the queue.")
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                }
            }

            Spacer(minLength: 0)

            // Auto-encode: Manual vs Automatic
            TabSelector(selection: Binding(
                get: { autoEncodeOnDrop ? ModeTab.automatic : ModeTab.manual },
                set: { autoEncodeOnDrop = ($0 == .automatic) }
            ))
            .frame(width: StyleConstants.headerPickerIdealWidth,
                   height: StyleConstants.headerModeToggleHeight)

            Spacer(minLength: 0)

            // Local vs Deadline
            RenderfarmToggle(runMode: $runMode)
                .environmentObject(state)
        }
        .padding(.vertical, StyleConstants.headerBarVerticalPadding)
        .padding(.horizontal, StyleConstants.panelPadding)
        .background(StyleConstants.panelBackground)
    }
}


private struct RenderfarmToggle: View {
    @Binding var runMode: RunMode
    @EnvironmentObject private var state: AppState

    private var isRemote: Bool { runMode == .remoteDeadline }
    private var isAvailable: Bool { state.deadlineAvailable || isRemote }

    var body: some View {
        Toggle(isOn: Binding(
            get: { isRemote },
            set: { desired in
                if desired {
                    if state.deadlineAvailable { runMode = .remoteDeadline }
                } else {
                    runMode = .localFFmpeg
                }
            }
        )) {
            Text("Renderfarm")
                .fontWeight(.semibold)
                .foregroundStyle(labelColor)
        }
        .toggleStyle(.switch)
        .tint(Color.accentColor)
        .disabled(!isAvailable)
        .help(state.deadlineAvailable ? "Toggle between Local and Renderfarm modes." : "Renderfarm unavailable; stay in Local mode.")
    }

    private var labelColor: Color {
        if !isAvailable { return StyleConstants.headerInactiveLabel }
        if isRemote { return Color.primary }
        return StyleConstants.headerInactiveLabel
    }
}

private enum ModeTab: Hashable {
    case manual
    case automatic
}

private struct TabSelector: View {
    @Binding var selection: ModeTab

    private var manualSelected: Bool { selection == .manual }

    var body: some View {
        let width = StyleConstants.headerPickerIdealWidth
        let halfWidth = width / 2
        let padding: CGFloat = 2

        ZStack(alignment: manualSelected ? .leading : .trailing) {
            Capsule()
                .fill(Color.primary.opacity(0.12))

            Capsule()
                .fill(StyleConstants.panelFill)
                .frame(width: halfWidth - padding * 2,
                       height: StyleConstants.headerModeToggleHeight - padding * 2)
                .padding(padding)
        }
        .overlay(alignment: .center) {
            HStack(spacing: 0) {
                tabButton(title: "Interactive", tab: .manual, isActive: manualSelected)
                    .frame(width: halfWidth)
                tabButton(title: "Automatic", tab: .automatic, isActive: !manualSelected)
                    .frame(width: halfWidth)
            }
        }
        .contentShape(Rectangle())
        .frame(width: width,
               height: StyleConstants.headerModeToggleHeight)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(manualSelected ? "Interactive" : "Automatic")
        .accessibilityHint("Double tap to switch encode workflow")
    }

    private func tabButton(title: String, tab: ModeTab, isActive: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = tab
            }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundColor(Color.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
