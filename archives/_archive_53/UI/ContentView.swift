//
//  ContentView.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/10/25.
//

import SwiftUI

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct ContentView: View {

    @EnvironmentObject var state: AppState
    @StateObject private var exportController = QueueExportController()

    @State private var isShowingQueueImporter = false
    @State private var queueImportMode: QueueImportMode = .replace

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Main column: Options (top) + DZ (bottom), unified scroll
                RightSideContent()
                    .environmentObject(state)

                // Footer with status + main progress bar
                FooterOverlay()
                    .environmentObject(state)
            }

            if state.isRobotMode {
                RobotModeOverlayView()
                    .environmentObject(state)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .sheet(isPresented: $state.showPreferences) {
            UI_PreferencesView()
                .environmentObject(state)
        }
        .frame(
            minWidth: StyleConstants.windowMinWidth,
            minHeight: StyleConstants.windowMinHeight
        )
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

        // Contextual menu Import Media
        .onReceive(NotificationCenter.default.publisher(for: .mrEncodeImportMediaRequested)) { _ in
            #if os(macOS)
            presentImportMediaPanel()
            #endif
        }

        // Contextual menu Save Queue
        .onReceive(NotificationCenter.default.publisher(for: .mrEncodeSaveQueueRequested)) { _ in
            exportController.beginExport(items: state.files)
        }

        // Contextual menu Open Queue
        .onReceive(NotificationCenter.default.publisher(for: .mrEncodeOpenQueueRequested)) { _ in
            queueImportMode = .replace
            isShowingQueueImporter = true
        }

        // Contextual menu Append Queue
        .onReceive(NotificationCenter.default.publisher(for: .mrEncodeAppendQueueRequested)) { _ in
            queueImportMode = .append
            isShowingQueueImporter = true
        }

        .fileImporter(
            isPresented: $isShowingQueueImporter,
            allowedContentTypes: [.json],          // <- force simplest case for now
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                state.importQueue(from: url, mode: queueImportMode)

            case .failure(let error):
                state.pushMessage(level: .error, "Open Queue failed: \(error.localizedDescription)")
            }
        }
        
        // Keep a toolbar lane for DrEncode, but show nothing in MrEncode
        .toolbar {
            ToolbarItem(placement: .principal) {
                EmptyView()
            }

            // Prefs gear in the titlebar, near the stoplights
            ToolbarItem(placement: .navigation) {
                Button(action: { state.showPreferences = true }) {
                    Image(systemName: "gearshape.fill")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help("Preferences")
            }
            
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: StyleConstants.hoverAnimationDuration)) {
                        state.isRobotMode.toggle()
                    }
                } label: {
                    Image(systemName: state.isRobotMode ? "xmark.circle.fill" : "eye.fill")
                }
                .help(state.isRobotMode ? "Exit Robot Mode" : "Robot Mode")
            }
        }
        // Make titlebar/toolbar match the app background, no seam
        .toolbarBackground(StyleConstants.globalBackground, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
                
        #if os(macOS)
        .background(
            KeyEventCatcher { event in
                switch event.keyCode {

                case 51, 117: // Backspace, Delete
                    state.removeSelectedQueueMedia()
                    return true

                case 126: // Up arrow / keypad up
                    state.selectPreviousQueueRow()
                    return true

                case 125: // Down arrow / keypad down
                    state.selectNextQueueRow()
                    return true

                case 123: // Left arrow
                    state.collapseSelectedQueueRow()
                    return true

                case 124: // Right arrow
                    state.expandSelectedQueueRow()
                    return true

                case 36, 76: // Return, keypad Enter
                    state.toggleExpandedForSelection()
                    return true

                default:
                    return false
                }
            }
        )
        #endif

        .fileExporter(
            isPresented: $exportController.isExporting,
            document: exportController.exportDoc,
            contentType: .mrqQueue,
            defaultFilename: "MrEncode_Queue.mrq"
        ) { result in
            exportController.handleExportResult(result)
        }
    }

    // MARK: - Import Media Panel (macOS)

    #if os(macOS)
    private func presentImportMediaPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Media"
        panel.message = "Select QuickTime files (.mov) or folders (top-level scan only)."
        panel.prompt = "Import"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = [UTType.movie, UTType.quickTimeMovie]

        panel.begin { response in
            guard response == .OK else { return }
            state.importMedia(from: panel.urls, alertTitle: "Add Processing")
        }
    }
    #endif
}

// MARK: - Right-side layout: Options above DZ, DZ fills remaining space, unified scroll

private struct RightSideContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: StyleConstants.sectionSpacing) {

                        // --- Options panel (top, natural height) ---
                        OptionsPanel()
                            .environmentObject(state)

                        // --- Drop Zone / Queue panel (fills remaining vertical space) ---
                        UI_Queue(
                            fixedHeight: nil,
                            isAutoMode: false,
                            showInternalHandle: false
                        )
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration),
                               value: state.settings.presetsExpanded)
                    .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration),
                               value: state.settings.generalExpanded)
                    .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration),
                               value: state.settings.scaleExpanded)
                    .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration),
                               value: state.settings.nclcExpanded)
                    .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration),
                               value: state.settings.overlaysExpanded)
                    .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration),
                               value: state.settings.deadlineExpanded)
                    .padding(.horizontal, StyleConstants.contentHorizontalPadding)
                    .padding(.top, StyleConstants.contentVerticalPadding)
                    .padding(.bottom, StyleConstants.panelSpacing)
                    // Make the stack at least as tall as the viewport so DZ can
                    // expand to fill any extra space below Options.
                    .frame(
                        maxWidth: .infinity,
                        minHeight: proxy.size.height,
                        alignment: .top
                    )
                }
                .scrollIndicators(.automatic)
                .background(StyleConstants.globalBackground)
            }

            // Right gutter to keep any scrollbar off the rounded panel edge
            Rectangle()
                .fill(StyleConstants.panelBackground)
                .frame(width: StyleConstants.scrollBarMarginWidth)
        }
        .background(StyleConstants.globalBackground)
    }
}


// MARK: - Options Panel

/// Presets card + a stack of separate option cards (Compression, Scale & Crop, NCLC, Overlay)
/// Presets chevron controls whether the other cards are shown.
private struct OptionsPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let isExpanded = state.settings.presetsExpanded

        VStack(spacing: StyleConstants.sectionSpacing) {

            // --- Presets card (folded-top spacing rule) ---
            OptionCard(vPadding: isExpanded ?
                       StyleConstants.panelPaddingV_expanded :
                       StyleConstants.panelPaddingV_folded)
            {
                UI_PresetsDroplets(isExpanded: $state.settings.presetsExpanded)
                    .environmentObject(state)
            }

            // --- Additional option cards (expanded only) ---
            if isExpanded {
                OptionCard(vPadding: StyleConstants.panelPaddingV_expanded) {
                    UI_CompressionOptions()
                }

                OptionCard(vPadding: StyleConstants.panelPaddingV_expanded) {
                    UI_ScaleCropOptions()
                }

                OptionCard(vPadding: StyleConstants.panelPaddingV_expanded) {
                    UI_NCLCOptions()
                }

                OptionCard(vPadding: StyleConstants.panelPaddingV_expanded) {
                    UI_OverlayOptions()
                }
                
                if state.settings.runMode == .remoteDeadline
                    || state.deadlineAvailable
                    || state.isRefreshingDeadline
                    || state.settings.lastDeadlineFetch != nil
                {
                    OptionCard(vPadding: StyleConstants.panelPaddingV_expanded) {
                        UI_DeadlineOptions()
                    }
                }
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration), value: state.settings.presetsExpanded)
    }
}


// MARK: - Generic option card wrapper

private struct OptionCard<Content: View>: View {
    let vPadding: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, StyleConstants.panelPaddingH)
        .padding(.vertical, vPadding)
        .background(
            RoundedRectangle(cornerRadius: StyleConstants.panelCornerRadius, style: .continuous)
                .fill(StyleConstants.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StyleConstants.panelCornerRadius, style: .continuous)
                .strokeBorder(
                    Color.secondary.opacity(StyleConstants.strokeOpacityNormal),
                    lineWidth: StyleConstants.borderLineWidth
                )
        )
    }
}


// MARK: - Footer Overlay

private struct FooterOverlay: View {
    @EnvironmentObject var state: AppState
    @StateObject private var footerViewModel = FooterViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Log window removed: keep logging behavior, just don’t render it
            /*
            if footerViewModel.shouldShowMessages(state.uiMessages) {
                UI_MessageArea()
                    .environmentObject(state)
                    .padding(.top, StyleConstants.footerTopPadding)
            }
            */

            if state.isBackgroundProcessing {
                BackgroundProgressBanner(
                    progress: state.backgroundProgress,
                    text: "Processing metadata..."
                )
            }

            FooterControls()
                .environmentObject(state)
                .environmentObject(footerViewModel)
        }
        .padding(.horizontal, StyleConstants.footerHorizontalPadding)
        .padding(.bottom, StyleConstants.footerBottomPadding)
        .background(StyleConstants.footerBackground)
        .ignoresSafeArea(edges: .bottom)
        .onAppear { footerViewModel.bind(to: state) }
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


// MARK: - Footer Controls

private struct FooterControls: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var footerViewModel: FooterViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(alignment: StyleConstants.footerStatusAlignment, spacing: 16) {

            // CLICKABLE STATUS / LOG AREA
            Button {
                openWindow(id: "log-viewer")
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        footerViewModel.formatStatusLine(
                            files: state.files,
                            hasSelection: !state.selectedIDs.isEmpty,
                            runMode: state.settings.runMode
                        )
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if let timeEstimate = footerViewModel.timeEstimateText {
                        Text(timeEstimate)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(
                    minHeight: StyleConstants.footerStatusMinHeight,
                    alignment: .top
                )
                .contentShape(Rectangle())   // critical: whole block clickable
            }
            .buttonStyle(.plain)
            .help("Open full log")

            Spacer()

            if footerViewModel.shouldShowFooterBatchProgress(files: state.files) {
                ZStack {
                    ProgressView(value: footerViewModel.globalProgress(files: state.files))
                        .progressViewStyle(.linear)
                    if let overlay = footerViewModel.progressOverlayLabel(
                        files: state.files,
                        settings: state.settings
                    ) {
                        Text(overlay)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: 160)
            }
        }
    }
}



// MARK: - Settings Revalidation

private struct RevalidateOnSettingsChange: ViewModifier {
    @EnvironmentObject var state: AppState

    func body(content: Content) -> some View {
        content
            .onChange(of: state.settings.bypassHEVC) { _ in state.requestRevalidate() }
            .onChange(of: state.settings.scale) { _ in state.requestRevalidate() }
            .onChange(of: state.settings.outputSuffix) { _ in state.requestRevalidate() }
            .onChange(of: state.settings.nclcTag) { _ in state.requestRevalidate() }
            .onChange(of: state.settings.nclcFilenameLabel) { _ in state.requestRevalidate() }
            .onChange(of: state.settings.burnInFrames) { _ in state.requestRevalidate() }
            .onChange(of: state.settings.burnInTimecode) { _ in state.requestRevalidate() }
            .onChange(of: state.settings.burnInFilename) { _ in state.requestRevalidate() }
            .onChange(of: state.settings.pool) { _ in state.requestRevalidate() }
            .onChange(of: state.settings.group) { _ in state.requestRevalidate() }
    }
}


