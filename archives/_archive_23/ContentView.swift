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
                VStack(spacing: 16) {
                    header
                    UI_Queue()
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(C.pad)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        UI_Queue()

                        // New order
                        UI_MainOptions()      // Compression & Resizing
                        UI_NCLCOptions()      // NCLC Tagging
                        UI_OverlayOptions()   // Overlays
                        UI_DeadlineOptions()  // unchanged
                    }
                    .padding(C.pad)
                    .padding(.bottom, C.actionBarHeight + C.pad)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !state.settings.autoEncodeOnDrop {
                VStack(spacing: C.messageSpacing) {
                    // Message Area above the buttons
                    UI_MessageArea()
                        .environmentObject(state)
                        .padding(.horizontal, C.pad)

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

    // MARK: - Header
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
            ZStack {
                Text(clearGhost).opacity(0)
                Button(clearTitle, action: onClear).disabled(!canClear)
            }
            Spacer()
            ZStack {
                Text(encodeGhost).opacity(0)
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
