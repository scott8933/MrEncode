//
// MARK: - ContentView.swift (Updated - Complete Version)
//

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
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    var body: some View {
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
        .sheet(isPresented: $state.showPreferences) {
            UI_PreferencesView().environmentObject(state)
        }
        .frame(minWidth: C.minW, minHeight: C.minH)
        .onChange(of: state.settings.runMode) { (newMode: RunMode) in
            DispatchQueue.main.async {
                state.revalidateFilesForCurrentMode()
            }
            if newMode == .remoteDeadline && !state.deadlineAvailable {
                state.refreshDeadlineOptions()
            }
        }
        .modifier(RevalidateOnSettingsChange())
        .onAppear {
            state.revalidateFilesForCurrentMode()
        }
    }
}

private struct BackgroundProgressBanner: View {
    let progress: Double
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: progress)
                .frame(width: 100)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.blue),
            alignment: .top
        )
    }
}

private struct FooterControls: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var footerViewModel: FooterViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            // Status Text
            VStack(alignment: .leading, spacing: 2) {
                Text(footerViewModel.formatStatusLine(
                    files: state.files,
                    hasSelection: !state.selectedIDs.isEmpty,
                    runMode: state.settings.runMode
                ))
                .font(.caption)
                .foregroundColor(.secondary)
                
                if let timeEstimate = footerViewModel.formatTimeEstimate(
                    files: state.files,
                    hasSelection: !state.selectedIDs.isEmpty,
                    settings: state.settings
                ) {
                    Text(timeEstimate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Progress Bar
            if footerViewModel.shouldShowProgress(files: state.files) {
                ProgressView(value: footerViewModel.globalProgress(files: state.files))
                    .frame(width: 120)
            }
            
            // Controls
            HStack(spacing: 8) {
                Button(footerViewModel.cancelButtonTitle(files: state.files)) {
                    state.cancelAllEncoding()
                }
                .disabled(!footerViewModel.cancelButtonEnabled(files: state.files))
                
                Button(footerViewModel.submitButtonTitle(
                    hasSelection: !state.selectedIDs.isEmpty,
                    runMode: state.settings.runMode
                )) {
                    let chosen = state.selectedItemsOrAll().filter { $0.isChecked && $0.status == .queued }
                    if chosen.isEmpty {
                        state.pushMessage(level: .warning, "No files ready to encode", filename: nil)
                        return
                    }
                    state.submit(items: chosen)
                }
                .disabled(!footerViewModel.submitButtonEnabled(
                    files: state.files,
                    hasSelection: !state.selectedIDs.isEmpty
                ))
                .keyboardShortcut(.return, modifiers: .command)
                
                Button("Preferences") {
                    state.showPreferences = true
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Revalidation modifier (collapses many onChange lines)

private struct RevalidateOnSettingsChange: ViewModifier {
    @EnvironmentObject var state: AppState
    
    func body(content: Content) -> some View {
        content
            .onChange(of: state.settings.bypassHEVC) { _ in
                state.revalidateFilesForCurrentMode()
            }
            .onChange(of: state.settings.scale) { _ in
                state.revalidateFilesForCurrentMode()
            }
            .onChange(of: state.settings.outputSuffix) { _ in
                state.revalidateFilesForCurrentMode()
            }
            .onChange(of: state.settings.nclcTag) { _ in
                state.revalidateFilesForCurrentMode()
            }
            .onChange(of: state.settings.nclcFilenameLabel) { _ in
                state.revalidateFilesForCurrentMode()
            }
            .onChange(of: state.settings.burnInFrames) { _ in
                state.revalidateFilesForCurrentMode()
            }
            .onChange(of: state.settings.burnInTimecode) { _ in
                state.revalidateFilesForCurrentMode()
            }
            .onChange(of: state.settings.burnInFilename) { _ in
                state.revalidateFilesForCurrentMode()
            }
            .onChange(of: state.settings.pool) { _ in
                state.revalidateFilesForCurrentMode()
            }
            .onChange(of: state.settings.group) { _ in
                state.revalidateFilesForCurrentMode()
            }
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

                UI_Queue(fixedHeight: 300, isAutoMode: false)  // ← MOVE THIS TO TOP

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
    @StateObject private var footerViewModel = FooterViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            if footerViewModel.shouldShowMessages(state.uiMessages) {
                UI_MessageArea()
                    .environmentObject(state)
            }
            
            if state.isBackgroundProcessing {
                BackgroundProgressBanner(
                    progress: state.backgroundProgress,
                    text: "Processing metadata..."
                )
            }
            
            if !state.settings.autoEncodeOnDrop {
                FooterControls()
                    .environmentObject(state)
                    .environmentObject(footerViewModel)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(.bar.opacity(0.9))
        .overlay(Divider(), alignment: .top)
        .ignoresSafeArea(edges: .bottom)
    }
}
