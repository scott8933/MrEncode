// ContentView.swift — fix cropped DZ border by sizing Top Pane from measured header height
// (Queue Window remains top-anchored; empty-state stays truly centered)

import SwiftUI
import AppKit


struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var queueHeight: CGFloat = StyleConstants.queueDefaultHeight

    var body: some View {
        VStack(spacing: 0) {
            if state.settings.autoEncodeOnDrop {
                AutoModeContent()
                    .environmentObject(state)
            } else {
                ManualModeContent(queueHeight: $queueHeight)
                    .environmentObject(state)
            }

            FooterOverlay()
                .environmentObject(state)
        }
        .sheet(isPresented: $state.showPreferences) {
            UI_PreferencesView().environmentObject(state)
        }
        .frame(minWidth: StyleConstants.windowMinWidth, minHeight: StyleConstants.windowMinHeight)
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

private struct AutoModeContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: StyleConstants.sectionSpacing) {
            UI_HeaderBar(
                title: state.isDropletMode ? "MrHEVC Droplet" : "MrHEVC",
                runMode: $state.settings.runMode,
                autoEncodeOnDrop: $state.settings.autoEncodeOnDrop
            )
            UI_Queue(fixedHeight: nil, isAutoMode: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, StyleConstants.contentHorizontalPadding)
        .padding(.top, StyleConstants.contentVerticalPadding)
        .background(StyleConstants.globalBackground)
    }
}

// ContentView.swift — fixed ManualModeContent (clean, constant-driven)

private struct ManualModeContent: View {
    @EnvironmentObject var state: AppState
    @Binding var queueHeight: CGFloat

    private let minQueueHeight: CGFloat = StyleConstants.queueMinHeight
    private let maxQueueHeight: CGFloat = StyleConstants.queueMaxHeight

    var body: some View {
        VStack(spacing: 0) {
            // TOP PANE: header chrome + Queue Window, sized by constants
            VStack(spacing: StyleConstants.panelSpacing) {
                UI_HeaderBar(
                    title: state.isDropletMode ? "MrHEVC Droplet" : "MrHEVC",
                    runMode: $state.settings.runMode,
                    autoEncodeOnDrop: $state.settings.autoEncodeOnDrop
                )

                HStack(spacing: 0) {
                    UI_Queue(fixedHeight: queueHeight, isAutoMode: false, showInternalHandle: false)
                        .frame(height: queueHeight, alignment: .top)   // Queue Window height is authoritative
                        .frame(maxWidth: .infinity, alignment: .top)

                    // Outer gutter to keep outer scrollbar from overlapping panel edge
                    Rectangle()
                        .fill(StyleConstants.panelBackground)
                        .frame(width: StyleConstants.scrollBarMarginWidth)
                }
            }
            .padding(.horizontal, StyleConstants.contentHorizontalPadding)
            .padding(.top, StyleConstants.contentVerticalPadding)
            .padding(.bottom, StyleConstants.topPaneBottomPadding) // prevents rounded DZ from clipping
            .background(StyleConstants.globalBackground)
            .frame(
                height: StyleConstants.topPaneChromeMin
                      + queueHeight
                      + StyleConstants.topPaneBottomPadding,
                alignment: .top
            )

            // AFFORDANCE splitter
            SimpleResizeHandle(
                height: $queueHeight,
                minHeight: minQueueHeight,
                maxHeight: maxQueueHeight
            )
            .background(StyleConstants.globalBackground)

            // BOTTOM PANE (Options): absorbs outer window resize between Affordance and Messages
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: StyleConstants.sectionSpacing) {
                        UI_PresetsDroplets()
                        UI_CompressionOptions()
                        UI_ScaleCropOptions()
                        UI_NCLCOptions()
                        UI_OverlayOptions()
                        UI_DeadlineOptions()
                    }
                    .padding(.horizontal, StyleConstants.contentHorizontalPadding)
                    .padding(.vertical, StyleConstants.panelSpacing)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.automatic)
                .frame(
                    minHeight: StyleConstants.optionsMinHeight,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .layoutPriority(1) // <- this pane takes the slack between Affordance and Messages
                .background(StyleConstants.globalBackground)

                // Right gutter (keeps outer scrollbar off the rounded panel edges)
                Rectangle()
                    .fill(StyleConstants.panelBackground)
                    .frame(width: StyleConstants.scrollBarMarginWidth)
            }
            .background(StyleConstants.globalBackground)        }
        .background(StyleConstants.globalBackground)
    }
}

// ContentView.swift — FooterOverlay with consistent top margin above the Messaging Area

private struct FooterOverlay: View {
    @EnvironmentObject var state: AppState
    @StateObject private var footerViewModel = FooterViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if footerViewModel.shouldShowMessages(state.uiMessages) {
                UI_MessageArea()
                    .environmentObject(state)
                    .padding(.top, StyleConstants.footerTopPadding) // NEW: keep gap when expanded/collapsed
            }

            if state.isBackgroundProcessing {
                BackgroundProgressBanner(
                    progress: state.backgroundProgress,
                    text: "Processing metadata..."
                )
            }

            if state.settings.autoEncodeOnDrop {
                AutoEncodeFooter()
                    .environmentObject(state)
                    .environmentObject(footerViewModel)
            } else {
                FooterControls()
                    .environmentObject(state)
                    .environmentObject(footerViewModel)
            }
        }
        .padding(.horizontal, StyleConstants.footerHorizontalPadding)
        .padding(.bottom, StyleConstants.footerBottomPadding)
        .background(StyleConstants.footerBackground)
        .overlay(Divider(), alignment: .top)
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
            Rectangle().frame(height: 1).foregroundColor(.blue),
            alignment: .top
        )
    }
}

private struct FooterControls: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var footerViewModel: FooterViewModel

    var body: some View {
        HStack(alignment: StyleConstants.footerStatusAlignment, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(footerViewModel.formatStatusLine(
                    files: state.files,
                    hasSelection: !state.selectedIDs.isEmpty,
                    runMode: state.settings.runMode
                ))
                .font(.caption)
                .foregroundColor(.secondary)

                if let timeEstimate = footerViewModel.timeEstimateText {
                    Text(timeEstimate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minHeight: StyleConstants.footerStatusMinHeight, alignment: .top)

            Spacer()

            if footerViewModel.shouldShowProgress(files: state.files) {
                ZStack {
                    ProgressView(value: footerViewModel.globalProgress(files: state.files))
                        .progressViewStyle(.linear)
                    if let overlay = footerViewModel.progressOverlayLabel(files: state.files, settings: state.settings) {
                        Text(overlay)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: 160)
            }

            HStack(spacing: 8) {
                Button("Cancel") { state.cancelAllEncoding() }
                    .disabled(!state.files.contains { $0.status == .encoding })

                Button("Encode") {
                    if state.settings.runMode == .remoteDeadline && !state.settings.deadlinePoolsValid {
                        state.pushMessage(
                            level: .warning,
                            "Deadline encode blocked — you must set a Pool in Deadline Options first.",
                            filename: nil,
                            code: .farmPath,
                            originKey: "encode"
                        )
                        return
                    }

                    let chosen = state.files.filter { $0.isChecked && $0.status == .queued }
                    if chosen.isEmpty {
                        state.pushMessage(level: .warning, "No files ready to encode", filename: nil)
                        return
                    }
                    state.submit(items: chosen)
                }
                .disabled(
                    !state.files.contains { $0.isChecked && $0.status == .queued }
                    || (state.settings.runMode == .remoteDeadline && !state.settings.deadlinePoolsValid)
                )
                .help("Set a Pool in the Deadline Options panel before encoding.")
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

private struct AutoEncodeFooter: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var footerViewModel: FooterViewModel

    var body: some View {
        HStack(alignment: StyleConstants.footerStatusAlignment, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(footerViewModel.formatStatusLine(
                    files: state.files,
                    hasSelection: !state.selectedIDs.isEmpty,
                    runMode: state.settings.runMode
                ))
                .font(.caption)
                .foregroundColor(.secondary)

                if let timeEstimate = footerViewModel.timeEstimateText {
                    Text(timeEstimate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minHeight: StyleConstants.footerStatusMinHeight, alignment: .top)

            Spacer()

            ZStack {
                ProgressView(value: footerViewModel.globalProgress(files: state.files))
                    .progressViewStyle(.linear)
                if let overlay = footerViewModel.progressOverlayLabel(files: state.files, settings: state.settings) {
                    Text(overlay)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 160)

            Button("Cancel") { state.cancelAllEncoding() }
                .disabled(!state.files.contains { $0.status == .encoding })
        }
    }
}

private struct RevalidateOnSettingsChange: ViewModifier {
    @EnvironmentObject var state: AppState

    func body(content: Content) -> some View {
        content
            .onChange(of: state.settings.bypassHEVC) { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.scale) { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.outputSuffix) { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.nclcTag) { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.nclcFilenameLabel) { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.burnInFrames) { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.burnInTimecode) { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.burnInFilename) { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.pool) { _ in state.revalidateFilesForCurrentMode() }
            .onChange(of: state.settings.group) { _ in state.revalidateFilesForCurrentMode() }
    }
}

private struct SimpleResizeHandle: View {
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    @State private var hovering = false

    var body: some View {
        HStack {
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: StyleConstants.borderLineWidth)

            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: StyleConstants.resizeHandleWidth + 16, height: StyleConstants.resizeHandleAreaHeight)
                    .contentShape(Rectangle())

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(hovering ? 0.6 : 0.4))
                    .frame(width: StyleConstants.resizeHandleWidth, height: StyleConstants.resizeHandleHeight)
            }
            .onHover { hovering = $0 }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let proposed = height + value.translation.height
                        height = max(minHeight, min(maxHeight, proposed))
                    }
            )

            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: StyleConstants.borderLineWidth)
        }
        .frame(height: StyleConstants.resizeHandleAreaHeight)
        .background(StyleConstants.controlBackgroundColor.opacity(0.5))
    }
}
