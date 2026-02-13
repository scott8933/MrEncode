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
                let hasHighlight = !state.selectedIDs.isEmpty   // <-- highlighted (list) rows

                UI_ActionBar(
                    canClear: !state.files.isEmpty,
                    canSubmit: state.files.contains { $0.isChecked && $0.status != .blocked }, // Encode uses checkboxes
                    onClear: {
                        if hasHighlight {
                            state.removeItems(withIDs: state.selectedIDs)
                            state.selectedIDs.removeAll()
                        } else {
                            state.clearAllNonEncoding()
                        }
                    },
                    onSubmit: {
                        let chosen = state.files.filter { $0.isChecked && $0.status != .blocked }
                        guard !chosen.isEmpty else {
                            state.pushMessage(level: .warning, "No items checked for Encode.", filename: nil)
                            return
                        }
                        state.submit(items: chosen) // routes to Local/Remote internally
                    },
                    runMode: state.settings.runMode,
                    hasSelection: hasHighlight    // <-- drives "Clear Selected" vs "Clear All" label
                )
                .frame(height: 52)
                .background(.bar)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
            }
        }


        .frame(minWidth: C.minW, minHeight: C.minH)
        .onChange(of: state.settings.runMode) { newMode in
            DispatchQueue.main.async {
                state.revalidateFilesForCurrentMode()
            }
            if newMode == .remoteDeadline && !state.deadlineAvailable {
                Task { await state.refreshDeadlineOptions(inBackground: true) }
            }
        }
        .onAppear {
            state.revalidateFilesForCurrentMode()
        }
        .onChange(of: state.settings.bypassHEVC)          { _ in state.revalidateFilesForCurrentMode() }
        .onChange(of: state.settings.scale)               { _ in state.revalidateFilesForCurrentMode() }
        .onChange(of: state.settings.outputSuffix)        { _ in state.revalidateFilesForCurrentMode() }
        .onChange(of: state.settings.nclcTag)             { _ in state.revalidateFilesForCurrentMode() }
        .onChange(of: state.settings.nclcFilenameLabel)   { _ in state.revalidateFilesForCurrentMode() }
        .onChange(of: state.settings.burnInFrames)        { _ in state.revalidateFilesForCurrentMode() }
        .onChange(of: state.settings.burnInTimecode)      { _ in state.revalidateFilesForCurrentMode() }
        .onChange(of: state.settings.burnInFilename)      { _ in state.revalidateFilesForCurrentMode() }



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
    private var encodeGhost: String { "Encode" }

    var body: some View {
        let clearTitle  = hasSelection ? "Clear Selected" : "Clear All"
        let encodeTitle = "Encode"

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
