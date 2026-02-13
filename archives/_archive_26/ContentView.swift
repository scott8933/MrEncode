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
                    UI_HeaderBar(
                        title: "MrHEVC",
                        runMode: $state.settings.runMode,
                        autoEncodeOnDrop: $state.settings.autoEncodeOnDrop
                    )
                    UI_Queue()
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(C.pad)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        UI_HeaderBar(
                            title: "MrHEVC",
                            runMode: $state.settings.runMode,
                            autoEncodeOnDrop: $state.settings.autoEncodeOnDrop
                        )
                        UI_Queue()

                        // New order
                        UI_CompressionOptions().environmentObject(state)
                        UI_ScaleCropOptions().environmentObject(state)
                        UI_NCLCOptions().environmentObject(state)
                        UI_OverlayOptions().environmentObject(state)
                        UI_DeadlineOptions().environmentObject(state)
                    }
                    .padding(C.pad)
                    .padding(.bottom, C.actionBarHeight + C.pad)
                }
            }
        }
        
        .overlay(alignment: .bottom) {
            if !state.settings.autoEncodeOnDrop {
                let hasHighlight = !state.selectedIDs.isEmpty

                UI_ActionBar(
                    canClear: !state.files.isEmpty,
                    canSubmit: state.files.contains { $0.isChecked && $0.status != .blocked },
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
                        state.submit(items: chosen) // your existing submit routes Local/Remote
                    },
                    runMode: state.settings.runMode,
                    hasSelection: hasHighlight,
                    showPreferences: $state.showPreferences // NEW
                )
                .frame(height: 52)
                .background(.bar)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .sheet(isPresented: $state.showPreferences) {
            UI_PreferencesView()                // ✅ correct type name
                .environmentObject(state)       // pass environment object to the sheet
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
}



