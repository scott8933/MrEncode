//
// MARK: - ContentView.swift (Revised - Separated Queue and Bottom Panels)
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState
    
    private enum C {
        static let pad: CGFloat = 16
        static let minW: CGFloat = 640
        static let minH: CGFloat = 720
        static let queueHeight: CGFloat = 280 // Fixed height for manual mode queue
        static let panelSpacing: CGFloat = 12
    }

    var body: some View {
        // Remove ZStack overlay approach - use VStack for clear separation
        VStack(spacing: 0) {
            if state.settings.autoEncodeOnDrop {
                AutoModeContent()
                    .environmentObject(state)
            } else {
                ManualModeContent()
                    .environmentObject(state)
            }
            
            // Bottom panels - no more overlay, direct VStack component
            BottomPanelsSection()
                .environmentObject(state)
        }
        .sheet(isPresented: $state.showPreferences) {
            UI_PreferencesView().environmentObject(state)
        }
        .frame(minWidth: 640, minHeight: 720)
        .onChange(of: state.settings.runMode) { (newMode: RunMode) in
            DispatchQueue.main.async {
                state.revalidateFilesForCurrentMode()
            }
            if newMode == .remoteDeadline && !state.deadlineAvailable {
                state.refreshDeadlineData()
            }
        }
        .modifier(RevalidateOnSettingsChange())
        .onAppear {
            state.revalidateFilesForCurrentMode()
        }
    }
}

// MARK: - Auto Mode (unchanged)

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

// MARK: - Manual Mode (Restructured - Three clear sections)

private struct ManualModeContent: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // SECTION 1: Header + Fixed Queue (no scrolling)
            VStack(spacing: 12) {
                UI_HeaderBar(
                    title: state.isDropletMode ? "MrHEVC Droplet" : "MrHEVC",
                    runMode: $state.settings.runMode,
                    autoEncodeOnDrop: $state.settings.autoEncodeOnDrop
                )
                
                // Fixed-height Queue section
                UI_Queue(fixedHeight: 280, isAutoMode: false)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Divider between queue and settings
            Divider()
                .padding(.horizontal, 16)
            
            // SECTION 2: Scrollable Settings Panels (independent scrolling)
            ScrollView {
                LazyVStack(spacing: 12) {
                    UI_PresetsDroplets()
                    UI_CompressionOptions()
                    UI_ScaleCropOptions()
                    UI_NCLCOptions()
                    UI_OverlayOptions()
                    UI_DeadlineOptions()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Bottom Panels Section (Replaces FooterOverlay)

private struct BottomPanelsSection: View {
    @EnvironmentObject var state: AppState
    @StateObject private var footerViewModel = FooterViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Top border for the bottom section
            Divider()
            
            // Panel stack with proper spacing
            VStack(spacing: 0) {
                // Messages panel
                if footerViewModel.shouldShowMessages(state.uiMessages) {
                    UI_MessageArea()
                        .environmentObject(state)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                }
                
                // Background processing banner
                if state.isBackgroundProcessing {
                    BackgroundProgressBanner(
                        progress: state.backgroundProgress,
                        text: "Processing metadata..."
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, footerViewModel.shouldShowMessages(state.uiMessages) ? 4 : 8)
                }
                
                // Control buttons (only in manual mode)
                if !state.settings.autoEncodeOnDrop {
                    FooterControls()
                        .environmentObject(state)
                        .environmentObject(footerViewModel)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(.bar.opacity(0.9))
    }
}

// MARK: - Background Progress Banner (unchanged)

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

// MARK: - Footer Controls (unchanged)

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
                Button("Cancel") {
                    state.cancelAllEncoding()
                }
                .disabled(!state.files.contains { $0.status == .encoding })
                
                Button("Encode") {
                    let chosen = state.files.filter { $0.isChecked && $0.status == .queued }
                    if chosen.isEmpty {
                        state.pushMessage(level: .warning, "No files ready to encode", filename: nil)
                        return
                    }
                    state.submit(items: chosen)
                }
                .disabled(!state.files.contains { $0.isChecked && $0.status == .queued })
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                
                Button(action: { state.showPreferences = true }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Preferences")
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Revalidation modifier (unchanged)

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
