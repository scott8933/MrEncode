import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState

    private enum C {
        static let pad: CGFloat = 16
        static let minW: CGFloat = 640
        static let minH: CGFloat = 720
        static let actionBarHeight: CGFloat = 52
    }

    var body: some View {
        Group {
            if state.settings.autoEncodeOnDrop {
                // Compact layout: Header → Queue, pinned to top
                VStack(spacing: 16) {
                    header
                    UI_Queue()
                    Spacer(minLength: 0) // keep content at top
                }
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .topLeading)
                .padding(C.pad)
            } else {
                // Full layout: Header → Queue → Main → Advanced → Deadline
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        UI_Queue()
                        UI_MainOptions()
                        UI_AdvancedOptions()
                        UI_DeadlineOptions()
                    }
                    .padding(C.pad)
                    .padding(.bottom, C.actionBarHeight + C.pad) // space for pinned bar
                }
            }
        }
        // Keep messages + footer always visible and tidy
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                // Compact log pane — auto-expands on errors
                UI_LogPane()

                // Footer buttons (only when NOT in auto-encode-on-drop)
                if !state.settings.autoEncodeOnDrop {
                    UI_ActionBar(
                        canClear: !state.files.isEmpty,
                        canSubmit: !state.files.isEmpty,
                        onClear: {
                            if state.selectedIDs.isEmpty {
                                state.clearAllNonEncoding()
                            } else {
                                state.removeItems(withIDs: state.selectedIDs)
                                state.selectedIDs.removeAll()
                            }
                        },
                        onSubmit: {
                            // Encode/Submit only selected if there is a selection; otherwise all.
                            let items = state.selectedIDs.isEmpty
                                ? state.files
                                : state.files.filter { state.selectedIDs.contains($0.id) }
                            state.submit(items: items)
                        },
                        runMode: state.settings.runMode,
                        hasSelection: !state.selectedIDs.isEmpty
                    )
                }
            }
            .background(.thinMaterial)          // subtle, “pro” look
            .padding(.bottom, 8)                // breathing room above the safe area
        }

        .frame(minWidth: C.minW, minHeight: C.minH)

        .onAppear {
            AppState.shared = state
            if !state.didBootstrapDeadline {
                state.bootstrapDeadlineLists()
            }
        }

        .onChange(of: state.settings.runMode) { newMode in
            state.revalidateFilesForCurrentMode()
            if newMode == .remoteDeadline && !state.deadlineAvailable {
                Task { state.refreshDeadlineOptions(inBackground: true) } // no `await`
            }
        }
        .onChange(of: state.settings.scale) { _ in
            state.preflightAllVisibleItems()
        }
    }

    // MARK: - Header (MrHEVC + Mode + Auto-Encode)
    private var header: some View {
        HStack(spacing: 12) {
            Text("MrHEVC").font(.largeTitle).bold()
            Spacer()

            // ✅ Correct Picker initializer: label + selection + content
            Picker("Mode", selection: $state.settings.runMode) {
                ForEach(RunMode.allCases) { mode in
                    // RunMode: String-backed; show human title from rawValue
                    Text(mode.rawValue).tag(mode)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)

            Toggle("Auto-encode on drop", isOn: $state.settings.autoEncodeOnDrop)
                .toggleStyle(.checkbox)
                .help("When on, dropped files will encode immediately with the current settings.")
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Bottom Action Bar
private struct UI_ActionBar: View {
    let canClear: Bool
    let canSubmit: Bool
    let onClear: () -> Void
    let onSubmit: () -> Void
    let runMode: RunMode
    let hasSelection: Bool

    // Longest possible labels (reserve width with "ghost" text)
    private var clearGhost: String { "Clear Selected" }
    private var encodeGhost: String {
        switch runMode {
        case .remoteDeadline: return "Submit Selected"
        default:              return "Encode Selected"
        }
    }

    var body: some View {
        let clearTitle  = hasSelection ? "Clear Selected" : "Clear All"
        let encodeTitle: String = {
            switch runMode {
            case .remoteDeadline: return hasSelection ? "Submit Selected" : "Submit All"
            default:              return hasSelection ? "Encode Selected" : "Encode All"
            }
        }()

        HStack(spacing: 12) {
            Spacer()

            ZStack {
                Text(clearGhost).opacity(0) // reserve width
                Button(clearTitle, action: onClear)
                    .disabled(!canClear)
                    .buttonStyle(.bordered)
            }

            ZStack {
                Text(encodeGhost).opacity(0) // reserve width
                Button(encodeTitle, action: onSubmit)
                    .disabled(!canSubmit)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .padding(.bottom, 160)
        .frame(minHeight: 44)
    }
}
