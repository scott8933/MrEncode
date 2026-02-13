import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState

    private enum C {
        static let pad: CGFloat = 16
        static let minW: CGFloat = 640
        static let minH: CGFloat = 720
        static let actionBarHeight: CGFloat = 52
        static let messageSpacing: CGFloat = 8
    }

    var body: some View {
        Group {
            if state.settings.autoEncodeOnDrop {
                // Compact layout: Header → Queue, pinned to top
                VStack(spacing: 16) {
                    header
                    UI_Queue()
                    Spacer(minLength: 0)                    // keep content at top
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
        .overlay(alignment: .bottom) {
            if !state.settings.autoEncodeOnDrop {
                VStack(spacing: C.messageSpacing) {
                    // Message Area above the buttons (compact, non-debuggy)
                    UI_MessageArea()
                        .environmentObject(state)
                        .padding(.horizontal, C.pad)

                    // Pinned action bar (unchanged behavior)
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
                            let items = state.selectedIDs.isEmpty
                                ? state.files
                                : state.files.filter { state.selectedIDs.contains($0.id) }
                            state.submit(items: items)
                        },
                        runMode: state.settings.runMode,
                        hasSelection: !state.selectedIDs.isEmpty
                    )
                    .frame(height: C.actionBarHeight)
                    .background(.bar)
                    .overlay(Divider(), alignment: .top)
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .frame(minWidth: C.minW, minHeight: C.minH)
        .onChange(of: state.settings.runMode) { newMode in
            state.revalidateFilesForCurrentMode()
            if newMode == .remoteDeadline && !state.deadlineAvailable {
                Task { await state.refreshDeadlineOptions(inBackground: true) }
            }
        }
    }

    // MARK: - Header (MrHEVC + Mode + Auto-Encode)
    private var header: some View {
        HStack(spacing: 12) {
            Text("MrHEVC").font(.largeTitle).bold()
            Spacer()

            Picker("Mode", selection: $state.settings.runMode) {
                ForEach(RunMode.allCases) { mode in
                    Text(mode.rawValue)
                        .fontWeight(mode == state.settings.runMode ? .semibold : .regular)
                        .foregroundColor(mode == state.settings.runMode ? .primary : .secondary)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .help("Choose Local (ffmpeg) or Remote (Deadline) execution.")

            Toggle("Auto-Encode", isOn: $state.settings.autoEncodeOnDrop)
                .help("Start encoding immediately when files are dropped.")
                .padding(.leading, 8)
        }
        .padding(.vertical, 4)
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

        HStack {
            // Fixed-width “Clear” via ghost text
            ZStack {
                Text(clearGhost).opacity(0) // reserve width
                Button(clearTitle, action: onClear)
                    .disabled(!canClear)
            }

            Spacer()

            // Fixed-width “Encode/Submit” via ghost text
            ZStack {
                Text(encodeGhost).opacity(0) // reserve width
                Button(encodeTitle, action: onSubmit)
                    .disabled(!canSubmit)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }
}
