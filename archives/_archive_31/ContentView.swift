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
                    
                    // Expanded queue that fills ALL available space to the footer
                    UI_Queue(fixedHeight: nil, isAutoMode: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        
                        // Manual resizable queue (no fixed height, shows resize handle)
                        UI_Queue(fixedHeight: nil, isAutoMode: false)

                        // Options panels
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
            VStack(spacing: 6) {
                // Always show Message Area in the footer
                UI_MessageArea()
                    .environmentObject(state)

                // Show the action bar only when not auto-encoding
                if !state.settings.autoEncodeOnDrop {
                    UI_ActionBar(
                        canClear: !state.files.isEmpty,
                        canSubmit: state.files.contains { $0.isChecked && $0.status != .blocked },
                        hasEncodingJobs: state.files.contains { $0.status == .encoding },
                        onClear: {
                            let hasHighlight = !state.selectedIDs.isEmpty
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
                            state.submit(items: chosen)
                        },
                        onCancelAll: {
                            state.cancelAllEncoding()
                        },
                        runMode: state.settings.runMode,
                        hasSelection: !state.selectedIDs.isEmpty,
                        showPreferences: $state.showPreferences
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(.bar.opacity(0.9))
            .overlay(Divider(), alignment: .top)
            .ignoresSafeArea(edges: .bottom)
        }

        .sheet(isPresented: $state.showPreferences) {
            UI_PreferencesView()
                .environmentObject(state)
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
