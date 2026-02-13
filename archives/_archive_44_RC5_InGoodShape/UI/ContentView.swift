//
// MARK: - ContentView.swift (Revised - Separated Queue and Bottom Panels)
//

import SwiftUI
import AppKit


struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var queueHeight: CGFloat = 280
    
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
                ManualModeContent(queueHeight: $queueHeight)
                    .environmentObject(state)
            }
            
            // Bottom panels - no more overlay, direct VStack component
            FooterOverlay()
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

// MARK: - Manual Mode

private struct ManualModeContent: View {
    @EnvironmentObject var state: AppState
    @Binding var queueHeight: CGFloat
    private let minQueueHeight: CGFloat = 140
    private let maxQueueHeight: CGFloat = 500
    
    var body: some View {
        VStack(spacing: 0) {
            // Header area
            VStack(spacing: 12) {
                UI_HeaderBar(
                    title: state.isDropletMode ? "MrHEVC Droplet" : "MrHEVC",
                    runMode: $state.settings.runMode,
                    autoEncodeOnDrop: $state.settings.autoEncodeOnDrop
                )
                
                // Queue with unified colors
                HStack(spacing: 0) {
                    UI_Queue(fixedHeight: queueHeight, isAutoMode: false, showInternalHandle: false)
                        .frame(height: queueHeight)
                    
                    // Scroll bar area
                    Rectangle()
                        .fill(AppColors.panelBackground) // CHANGED: Use AppColors
                        .frame(width: 14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .background(AppColors.globalBackground) // CHANGED: Use AppColors
            
            // Resize handle
            SimpleResizeHandle(
                height: $queueHeight,
                minHeight: minQueueHeight,
                maxHeight: maxQueueHeight
            )
            .background(AppColors.globalBackground) // CHANGED: Use AppColors
            
            // Settings panels
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        UI_PresetsDroplets()
                        UI_CompressionOptions()
                        UI_ScaleCropOptions()
                        UI_NCLCOptions()
                        UI_OverlayOptions()
                        UI_DeadlineOptions()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 100)
                }
                .scrollIndicators(.automatic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.globalBackground) // CHANGED: Use AppColors
                
                // Scroll bar area
                Rectangle()
                    .fill(AppColors.panelBackground) // CHANGED: Use AppColors
                    .frame(width: 14)
            }
            .background(AppColors.globalBackground) // CHANGED: Use AppColors
        }
        .background(AppColors.globalBackground) // CHANGED: Use AppColors
    }
}


// MARK: - Footer

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
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .background(AppColors.footerBackground) // CHANGED: Use AppColors
        .overlay(Divider(), alignment: .top)
        .ignoresSafeArea(edges: .bottom)
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

// MARK: - Unified Resize Handle

private struct SimpleResizeHandle: View {
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    
    @State private var hovering = false
    
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
            
            // Simple resize handle - no competing gestures
            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 80, height: 16)
                    .contentShape(Rectangle())
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(hovering ? 0.6 : 0.4))
                    .frame(width: 64, height: 4)
            }
            .onHover { hovering = $0 }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newHeight = height + value.translation.height
                        let clamped = max(minHeight, min(maxHeight, newHeight))
                        height = clamped
                    }
            )
            
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
        }
        .frame(height: 16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}
