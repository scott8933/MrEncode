// =============================
// File: UI_HeaderBar.swift - Simple Header Bar
// =============================

// UI_HeaderBar.swift — use consolidated widths from AppColors

import SwiftUI

struct UI_HeaderBar: View {
    let title: String
    @Binding var runMode: RunMode
    @Binding var autoEncodeOnDrop: Bool
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: StyleConstants.headerSpacing) {
            Text(title)
                .font(.largeTitle).bold()

            Spacer(minLength: 0)

            TabSelector(selection: Binding(
                get: { autoEncodeOnDrop ? ModeTab.automatic : ModeTab.manual },
                set: { autoEncodeOnDrop = ($0 == .automatic) }
            ))
            .frame(width: StyleConstants.headerPickerIdealWidth,
                   height: StyleConstants.headerModeToggleHeight)
            .help("Choose whether encoding starts manually or automatically.")

            Spacer(minLength: 0)

            Toggle("Renderfarm", isOn: Binding(
                get: { runMode == .remoteDeadline },
                set: { isEnabled in
                    if isEnabled {
                        if state.deadlineAvailable {
                            runMode = .remoteDeadline
                        }
                    } else {
                        runMode = .localFFmpeg
                    }
                }
            ))
            .toggleStyle(.switch)
            .disabled(!state.deadlineAvailable && runMode != .remoteDeadline)
            .help(state.deadlineAvailable ? "Toggle between Local and Renderfarm modes." : "Renderfarm unavailable; stay in Local mode.")
        }
        .padding(.vertical, StyleConstants.headerBarVerticalPadding)
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
                tabButton(title: "Manual", tab: .manual, isActive: manualSelected)
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
        .accessibilityLabel(manualSelected ? "Manual" : "Automatic")
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

private struct ModePillToggle: View {
    @Binding var runMode: RunMode

    private var localSelected: Bool { runMode == .localFFmpeg }

    var body: some View {
        GeometryReader { geo in
            let halfWidth = geo.size.width / 2
            let padding: CGFloat = 2

            ZStack(alignment: localSelected ? .leading : .trailing) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: halfWidth - padding * 2,
                           height: geo.size.height - padding * 2)
                    .padding(padding)
            }
            .overlay(alignment: .center) {
                HStack(spacing: 0) {
                    modeButton(title: "Local", mode: .localFFmpeg, isActive: localSelected)
                        .frame(width: halfWidth)
                    modeButton(title: "Renderfarm", mode: .remoteDeadline, isActive: !localSelected)
                        .frame(width: halfWidth)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    runMode = (runMode == .localFFmpeg) ? .remoteDeadline : .localFFmpeg
                }
            }
        }
        .frame(maxHeight: .infinity)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localSelected ? "Destination: Local" : "Destination: Renderfarm")
        .accessibilityHint("Double tap to toggle destination mode")
    }

    private func modeButton(title: String, mode: RunMode, isActive: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                runMode = mode
            }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundColor(isActive ? Color.white : Color.primary.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mode: \(title)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
