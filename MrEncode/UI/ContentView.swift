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
    
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    @EnvironmentObject var state: AppState
    @StateObject private var exportController = QueueExportController()

    @State private var isShowingQueueImporter = false
    @State private var queueImportMode: QueueImportMode = .replace
    @State private var dropZoneFrame: CGRect = .zero
    @State private var footerFrame: CGRect = .zero
    @State private var floatingControlsHeight: CGFloat = 0
    @State private var dropZoneTopY: CGFloat = 0  // Changed from .greatestFiniteMagnitude
    @State private var scrollOffset: CGFloat = 0  // Add this

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Main column: Options (top) + DZ (bottom), unified scroll
                MainContent()
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
        .coordinateSpace(name: FloatingC.coordSpaceName)
        .sheet(isPresented: $state.showPreferences) {
            UI_PreferencesView()
                .environmentObject(state)
        }
        .frame(
            minWidth: StyleConstants.Sizes.windowMinWidth,
            minHeight: StyleConstants.Sizes.windowMinHeight
        )

        .overlay {
            // Fade gradients layer (behind DZ stroke)
            FadeGradientsOverlay(
                dropZoneFrame: dropZoneFrame,
                footerFrame: footerFrame
            )
            .environmentObject(state)
        }

        .overlay {
            FloatingQueueControlsOverlay(
                dropZoneFrame: dropZoneFrame,
                dropZoneTopY: dropZoneTopY,
                footerFrame: footerFrame,
                floatingControlsHeight: $floatingControlsHeight,
                scrollOffset: scrollOffset
            )
            .environmentObject(state)
        }
        
        // Corner cutouts to make a nicer scroll mask
        .overlay {
            CornerCutoutsOverlay(
                dropZoneFrame: dropZoneFrame,
                footerFrame: footerFrame
            )
        }

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
        
        // Live drop zone frame updates
        .onReceive(NotificationCenter.default.publisher(for: .dropZoneFrameChanged)) { notification in
            if let frame = notification.object as? CGRect {
                dropZoneFrame = frame
                dropZoneTopY = frame.minY
            }
        }

        // Live footer frame updates (ADD THIS)
        .onReceive(NotificationCenter.default.publisher(for: .footerFrameChanged)) { notification in
            if let frame = notification.object as? CGRect {
                footerFrame = frame
            }
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
                        .font(.system(size: 15, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.primary)
                        .offset(x: 4)
                }
                .buttonStyle(.plain)
                .help("Preferences")
            }
            
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: StyleConstants.Motion.hoverAnimationDuration)) {
                        state.isRobotMode.toggle()
                    }
                } label: {
                    Image(systemName: state.isRobotMode ? "xmark.circle.fill" : "eye.fill")
                }
                .help(state.isRobotMode ? "Exit Robot Mode" : "Robot Mode")
            }
        }
        // Make titlebar/toolbar match the app background, no seam
        .toolbarBackground(C.bgApp, for: .windowToolbar)
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
        panel.message = "Select video files or folders (top-level scan only)."
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

private struct FloatingQueueControlsBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 24) {

            AutoEncodeFloatingButton()
                .environmentObject(state)

            Spacer(minLength: 20)

            EncodePauseCancelFloatingGroup()
                .environmentObject(state)

            TrashFloatingButton()
                .environmentObject(state)
        }
        .padding(.horizontal, StyleConstants.Spacing.panelPaddingV_expanded)
        .padding(.bottom, StyleConstants.Spacing.panelPaddingV_expanded)
    }
}


// MARK: - Main layout: Options above DZ, DZ fills remaining space, unified scroll

private struct MainContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }
    
    @State private var scrollViewID = "mainScroll"

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { outerGeo in
                ScrollView(.vertical) {
                    VStack(spacing: StyleConstants.Spacing.sectionSpacing) {

                        // Scroll tracker at top
                        Color.clear
                            .frame(height: 1)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: geo.frame(in: .global).minY - outerGeo.frame(in: .global).minY
                                    )
                                }
                            )

                        // --- Options panel (top, natural height) ---
                        OptionsPanel()
                            .environmentObject(state)

                        // --- Drop Zone / Queue panel ---
                        UI_Queue(
                            fixedHeight: nil,
                            isAutoMode: false,
                            showInternalHandle: false
                        )
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration),
                               value: state.settings.presetsExpanded)
                    .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration),
                               value: state.settings.generalExpanded)
                    .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration),
                               value: state.settings.scaleExpanded)
                    .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration),
                               value: state.settings.nclcExpanded)
                    .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration),
                               value: state.settings.overlaysExpanded)
                    .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration),
                               value: state.settings.deadlineExpanded)
                    .padding(.horizontal, StyleConstants.Spacing.contentHorizontalPadding)
                    .padding(.top, StyleConstants.Spacing.contentVerticalPadding)
                    .padding(.bottom, StyleConstants.Spacing.panelSpacing)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: outerGeo.size.height,
                        alignment: .top
                    )
                }
                .scrollIndicators(.automatic)
                .background(C.bgApp)
            }

            Rectangle()
                .fill(C.bgApp)
                .frame(width: StyleConstants.Spacing.scrollBarMarginWidth)
        }
        .background(C.bgApp)
    }
}


// MARK: - Options Panel

/// Presets card + a stack of separate option cards (Compression, Scale & Crop, NCLC, Overlay)
/// Presets chevron controls whether the other cards are shown.
private struct OptionsPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let isExpanded = state.settings.presetsExpanded

        VStack(spacing: StyleConstants.Spacing.sectionSpacing) {

            // --- Presets card (folded-top spacing rule) ---
            OptionCard(vPadding: isExpanded ?
                       StyleConstants.Spacing.panelPaddingV_expanded :
                       StyleConstants.Spacing.panelPaddingV_folded)
            {
                UI_PresetsDroplets(isExpanded: $state.settings.presetsExpanded)
                    .environmentObject(state)
            }

            // --- Additional option cards (expanded only) ---
            if isExpanded {
                OptionCard(vPadding: StyleConstants.Spacing.panelPaddingV_expanded) {
                    UI_CompressionOptions()
                }

                OptionCard(vPadding: StyleConstants.Spacing.panelPaddingV_expanded) {
                    UI_ScaleCropOptions()
                }

                OptionCard(vPadding: StyleConstants.Spacing.panelPaddingV_expanded) {
                    UI_NCLCOptions()
                }

                OptionCard(vPadding: StyleConstants.Spacing.panelPaddingV_expanded) {
                    UI_OverlayOptions()
                }
                
                if state.settings.runMode == .remoteDeadline
                    || state.deadlineAvailable
                    || state.isRefreshingDeadline
                    || state.settings.lastDeadlineFetch != nil
                {
                    OptionCard(vPadding: StyleConstants.Spacing.panelPaddingV_expanded) {
                        UI_DeadlineOptions()
                    }
                }
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration), value: state.settings.presetsExpanded)
    }
}


private struct OptionCard<Content: View>: View {
    let vPadding: CGFloat
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    var body: some View {
        let r = RoundedRectangle(
            cornerRadius: StyleConstants.Spacing.panelCornerRadius,
            style: .continuous
        )

        VStack(alignment: .leading, spacing: 0) {
            content
        }
        // Use semantic text; don't force per-panel text colors.
        .foregroundStyle(.primary)

        .padding(.horizontal, StyleConstants.Spacing.panelPaddingH)
        .padding(.vertical, vPadding)

        // Base panel fill
        .background(
            r.fill(C.bgPanel)
        )

        // Panel wash/tint OVER everything in the panel (including AppKit-backed controls)
        .overlay(
            r.fill(C.panelWash)
                .allowsHitTesting(false)
        )

        // Stroke stays last so it remains crisp
        .overlay(
            r.strokeBorder(
                C.strokeSubtle,
                lineWidth: StyleConstants.Borders.borderLineWidth
            )
        )
    }
}



// MARK: - Footer Overlay

private struct FooterOverlay: View {
    @EnvironmentObject var state: AppState
    @StateObject private var footerViewModel = FooterViewModel()
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

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
        .padding(.horizontal, StyleConstants.Spacing.footerHorizontalPadding)
        .padding(.bottom, StyleConstants.Spacing.footerBottomPadding)
        .background(C.bgInset)
        .ignoresSafeArea(edges: .bottom)
        .background(
            GeometryReader { geo in
                let frame = geo.frame(in: .named(FloatingC.coordSpaceName))
                Color.clear
                    .onAppear {
                        // Post initial frame on appear
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .footerFrameChanged,
                                object: frame
                            )
                        }
                    }
                    .preference(
                        key: FooterFramePreferenceKey.self,
                        value: frame
                    )
            }
        )
        .background(
            GeometryReader { geo in
                let frame = geo.frame(in: .named(FloatingC.coordSpaceName))
                Color.clear
                    .onChange(of: frame) { newFrame in
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: .footerFrameChanged,
                                object: newFrame
                            )
                        }
                    }
                    .preference(
                        key: FooterFramePreferenceKey.self,
                        value: frame
                    )
            }
        )
        .onAppear { footerViewModel.bind(to: state) }
    }
}

private struct BackgroundProgressBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }
    
    let progress: Double
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: progress)
                .frame(width: 100)

            Text(text)
                .font(.caption)
                .foregroundColor(C.textSecondary)

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
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    var body: some View {
        HStack(alignment: StyleConstants.Spacing.footerStatusAlignment, spacing: 16) {

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
                    .foregroundColor(C.textSecondary)

                    if let timeEstimate = footerViewModel.timeEstimateText {
                        Text(timeEstimate)
                            .font(.caption2)
                            .foregroundColor(C.textSecondary)
                    }
                }
                .frame(
                    minHeight: StyleConstants.Sizes.footerStatusMinHeight,
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
                            .foregroundColor(C.textSecondary)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: 160)
            }
        }
    }
}


// MARK: - Floating Controls Geometry (ContentCS)

private struct FloatingQueueControlsOverlay: View {
    @EnvironmentObject var state: AppState

    let dropZoneFrame: CGRect
    let dropZoneTopY: CGFloat
    let footerFrame: CGRect
    @Binding var floatingControlsHeight: CGFloat
    let scrollOffset: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    var body: some View {
        GeometryReader { geo in
            let sideInset: CGFloat = 12
            
            // TODO need to fix this - must be padding preventing it from moving lower
            let liftY: CGFloat = 00
            
            let gap = StyleConstants.Spacing.panelPaddingV_expanded
            
            let barHalf = floatingControlsHeight > 0 ? floatingControlsHeight * 0.5 : 23
            
            let dzResolved = dropZoneFrame.width > 1 && dropZoneFrame.height > 1

            if dzResolved {
                let dzMidX = dropZoneFrame.midX
                let barWidth = max(1, dropZoneFrame.width - (sideInset * 2))
                
                let footerTopY: CGFloat = footerFrame.minY > 0
                    ? footerFrame.minY
                    : geo.size.height - 80

                let targetBottomY = footerTopY - liftY
                let targetCenterY = targetBottomY - barHalf

                let minCenterY = dropZoneFrame.minY + gap + barHalf
                let maxCenterY = dropZoneFrame.maxY - gap - barHalf

                let finalCenterY = max(min(targetCenterY, maxCenterY), minCenterY)
                
                let visibleHeight = max(0, footerTopY - dropZoneFrame.minY)

                ZStack {
                    // Just the floating buttons now, gradients removed
                    FloatingQueueControlsBar()
                        .environmentObject(state)
                        .frame(width: barWidth)
                        .background(
                            GeometryReader { barGeo in
                                Color.clear.preference(
                                    key: FloatingControlsHeightPreferenceKey.self,
                                    value: barGeo.size.height
                                )
                            }
                        )
                        .position(x: dzMidX, y: finalCenterY)
                        .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration), value: barWidth)
                        .zIndex(5)
                }
                .mask {
                    RoundedRectangle(
                        cornerRadius: StyleConstants.Spacing.panelCornerRadius,
                        style: .continuous  // Add this - matches the DZ's corner style
                    )
                    .frame(width: dropZoneFrame.width, height: visibleHeight)
                    .position(
                        x: dropZoneFrame.midX,
                        y: dropZoneFrame.minY + visibleHeight / 2
                    )
                    .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration), value: dropZoneFrame.size)
                    .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration), value: visibleHeight)
                }
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


// MARK: Corner cutouts / fake rounded corner mask over DZ scroll

private struct CornerCutoutsOverlay: View {
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }
    
    let dropZoneFrame: CGRect
    let footerFrame: CGRect
    
    var body: some View {
        GeometryReader { geo in
            let r = StyleConstants.Spacing.panelCornerRadius
            let dzLeft = dropZoneFrame.minX
            let dzRight = dropZoneFrame.maxX
            let fixedTop = CGFloat(0)
            let fixedBottom = footerFrame.minY > 0 ? footerFrame.minY : geo.size.height - 80
            
            // Top-left corner fill
            Path { path in
                path.move(to: CGPoint(x: dzLeft, y: fixedTop))
                path.addLine(to: CGPoint(x: dzLeft, y: fixedTop + r))
                path.addQuadCurve(
                    to: CGPoint(x: dzLeft + r, y: fixedTop),
                    control: CGPoint(x: dzLeft, y: fixedTop)
                )
                path.addLine(to: CGPoint(x: dzLeft, y: fixedTop))
                path.closeSubpath()
            }
            .fill(C.bgApp)
            
            // Top-right corner fill
            Path { path in
                path.move(to: CGPoint(x: dzRight, y: fixedTop))
                path.addLine(to: CGPoint(x: dzRight, y: fixedTop + r))
                path.addQuadCurve(
                    to: CGPoint(x: dzRight - r, y: fixedTop),
                    control: CGPoint(x: dzRight, y: fixedTop)
                )
                path.addLine(to: CGPoint(x: dzRight, y: fixedTop))
                path.closeSubpath()
            }
            .fill(C.bgApp)
            
            // Bottom-left corner fill
            Path { path in
                path.move(to: CGPoint(x: dzLeft, y: fixedBottom))
                path.addLine(to: CGPoint(x: dzLeft, y: fixedBottom - r))
                path.addQuadCurve(
                    to: CGPoint(x: dzLeft + r, y: fixedBottom),
                    control: CGPoint(x: dzLeft, y: fixedBottom)
                )
                path.closeSubpath()
            }
            .fill(C.bgApp)
            
            // Bottom-right corner fill
            Path { path in
                path.move(to: CGPoint(x: dzRight, y: fixedBottom))
                path.addLine(to: CGPoint(x: dzRight, y: fixedBottom - r))
                path.addQuadCurve(
                    to: CGPoint(x: dzRight - r, y: fixedBottom),
                    control: CGPoint(x: dzRight, y: fixedBottom)
                )
                path.closeSubpath()
            }
            .fill(C.bgApp)
        }
        .allowsHitTesting(false)
    }
}


// MARK: - Gradient thing

private struct FadeGradientsOverlay: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }
    
    let dropZoneFrame: CGRect
    let footerFrame: CGRect
    
    var body: some View {
        GeometryReader { geo in
            let dzResolved = dropZoneFrame.width > 1 && dropZoneFrame.height > 1
            
            if dzResolved {
                let footerTopY: CGFloat = footerFrame.minY > 0
                    ? footerFrame.minY
                    : geo.size.height - 80
                
                let visibleHeight = max(0, footerTopY - dropZoneFrame.minY)
                
                ZStack {
                    // Top fade gradient (fixed to viewport top, not DZ top)
                    LinearGradient(
                        colors: [C.bgDropZone, Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: dropZoneFrame.width, height: 60)
                    .position(x: dropZoneFrame.midX, y: 30)  // Fixed to top of viewport
                    .allowsHitTesting(false)
                    
                    // Bottom fade gradient (behind buttons)
                    LinearGradient(
                        colors: [Color.clear, C.bgDropZone],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: dropZoneFrame.width, height: 100)
                    .position(x: dropZoneFrame.midX, y: footerTopY - 50)
                    .allowsHitTesting(false)
                }
                .mask {
                    RoundedRectangle(
                        cornerRadius: StyleConstants.Spacing.panelCornerRadius,
                        style: .continuous  // <- Add this
                    )                        .frame(width: dropZoneFrame.width, height: visibleHeight)
                        .position(
                            x: dropZoneFrame.midX,
                            y: dropZoneFrame.minY + visibleHeight / 2
                        )
                }
            }
        }
    }
}
