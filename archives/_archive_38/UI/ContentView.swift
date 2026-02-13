import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState

    private enum C {
        static let pad: CGFloat = 16
        static let minW: CGFloat = 640
        static let minH: CGFloat = 720
    }

    private struct FooterHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    var body: some View {
        // ZStack instead of a massive .overlay builder
        ZStack(alignment: .bottom) {
            if state.settings.autoEncodeOnDrop {
                AutoModeContent()
                    .environmentObject(state)
            } else {
                ManualModeContent()
                    .environmentObject(state)
            }

            FooterOverlay()
                .environmentObject(state)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: FooterHeightKey.self, value: proxy.size.height)
                    }
                )
        }
        .onPreferenceChange(FooterHeightKey.self) { state.footerHeight = $0 }
        .sheet(isPresented: $state.showPreferences) { UI_PreferencesView().environmentObject(state) }
        .frame(minWidth: C.minW, minHeight: C.minH)

        // Keep ONLY the heavyweight onChange with explicit type
        .onChange(of: state.settings.runMode) { (newMode: RunMode) in
            DispatchQueue.main.async { state.revalidateFilesForCurrentMode() }
            if newMode == .remoteDeadline && !state.deadlineAvailable {
                state.refreshDeadlineOptions()
            }
        }

        // Light revalidation triggers collapsed to a single helper
        .modifier(RevalidateOnSettingsChange())
        .onAppear { state.revalidateFilesForCurrentMode() }
    }
}

// MARK: - Subviews

private struct AutoModeContent: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 16) {
            UI_HeaderBar(
                title: state.isDropletMode ? "MrHEVC Droplet" : "MrHEVC",
                runMode: $state.settings.runMode,
                autoEncodeOnDrop: $state.settings.autoEncodeOnDrop
            )
            UI_Queue(fixedHeight: nil, isAutoMode: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }
}

private struct ManualModeContent: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                UI_HeaderBar(
                    title: state.isDropletMode ? "MrHEVC Droplet" : "MrHEVC",
                    runMode: $state.settings.runMode,
                    autoEncodeOnDrop: $state.settings.autoEncodeOnDrop
                )

                UI_Queue(fixedHeight: nil, isAutoMode: false)

                UI_PresetsDroplets()
                UI_CompressionOptions()
                UI_ScaleCropOptions()
                UI_NCLCOptions()
                UI_OverlayOptions()
                UI_DeadlineOptions()
            }
            .environmentObject(state)
            .padding(16)
            .padding(.bottom, state.footerHeight + 16)
        }
    }
}

private struct FooterOverlay: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 6) {
            UI_MessageArea().environmentObject(state)

            if !state.settings.autoEncodeOnDrop {
                UI_ActionBar(
                    canClear: !state.files.isEmpty,
                    canSubmit: state.files.contains { $0.isChecked && $0.status != .blocked },
                    hasEncodingJobs: state.files.contains { $0.status == .encoding },
                    onClear: {
                        if !state.selectedIDs.isEmpty {
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
                    onCancelAll: { state.cancelAllEncoding() },
                    runMode: state.settings.runMode,
                    hasSelection: !state.selectedIDs.isEmpty,
                    isBackgroundProcessing: state.isBackgroundProcessing,
                    showPreferences: $state.showPreferences
                )
                .environmentObject(state)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(.bar.opacity(0.9))
        .overlay(Divider(), alignment: .top)
        .ignoresSafeArea(edges: .bottom)
    }
}



// MARK: - Revalidation modifier (collapses many onChange lines)

private struct RevalidateOnSettingsChange: ViewModifier {
    @EnvironmentObject var state: AppState
    func body(content: Content) -> some View {
        content
            .onChange(of: state.settings.bypassHEVC)        { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.scale)             { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.outputSuffix)      { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.nclcTag)           { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.nclcFilenameLabel) { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.burnInFrames)      { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.burnInTimecode)    { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.burnInFilename)    { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.pool)              { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.group)             { _ in state.revalidateFilesForCurrentMode() }
    }
}
