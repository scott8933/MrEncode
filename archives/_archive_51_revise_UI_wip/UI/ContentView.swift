//
//  ContentView.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/10/25.
//


import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var queueHeight: CGFloat = StyleConstants.queueDefaultHeight

    var body: some View {
        VStack(spacing: 0) {
            // Main column: true SplitView (top: Queue/Drop Zone, bottom: Settings)
            ManualModeContent(queueHeight: $queueHeight)
                .environmentObject(state)
            
            // Footer with status + main progress bar
            FooterOverlay()
                .environmentObject(state)
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
        // Keep a toolbar lane for DrEncode, but show nothing in MrEncode
        .toolbar {
            ToolbarItem(placement: .principal) {
                EmptyView()
            }
        }
        // Make titlebar/toolbar match the app background, no seam
        .toolbarBackground(StyleConstants.globalBackground, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
    }
}

// MARK: - Main Layout (MrEncode) using Top/Bottom NSSplitView

private struct ManualModeContent: View {
    @EnvironmentObject var state: AppState
    @Binding var queueHeight: CGFloat

    private let minQueueHeight: CGFloat = StyleConstants.queueMinHeight
    private let minOptionsHeight: CGFloat = StyleConstants.optionsMinHeight

    var body: some View {
        TopBottomSplitView(
            top: TopPaneView().environmentObject(state),
            bottom: BottomPaneView().environmentObject(state),
            minTopHeight: minQueueHeight,
            minBottomHeight: minOptionsHeight,
            topHeight: $queueHeight
        )
        .background(StyleConstants.globalBackground)
    }
}

// MARK: - Top / Bottom Pane Content

/// Top pane = Queue / Drop Zone
/// Top pane = Queue / Drop Zone
private struct TopPaneView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            UI_Queue(
                fixedHeight: nil,       // SplitView controls height now
                isAutoMode: false,
                showInternalHandle: false
            )
            .frame(maxWidth: .infinity, alignment: .top)

            // Outer gutter to keep outer scrollbar from overlapping panel edge
            Rectangle()
                .fill(StyleConstants.panelBackground)
                .frame(width: StyleConstants.scrollBarMarginWidth)
        }
        // Horizontal + top padding so the DZ panel is inset nicely
        .padding(.horizontal, StyleConstants.contentHorizontalPadding)
        .padding(.top, StyleConstants.contentVerticalPadding)

        // ❌ IMPORTANT: no extra bottom padding here
        // The bottom of this view == bottom of the DZ card,
        // which is exactly where the (invisible) splitter lives.
        .background(StyleConstants.globalBackground)
    }
}


/// Bottom pane = consolidated Settings / Options
private struct BottomPaneView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
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
            .background(StyleConstants.globalBackground)

            // Right gutter (keeps outer scrollbar off the rounded panel edges)
            Rectangle()
                .fill(StyleConstants.panelBackground)
                .frame(width: StyleConstants.scrollBarMarginWidth)
        }
        .background(StyleConstants.globalBackground)
    }
}

// MARK: - NSSplitView wrapper for top/bottom split

/// Custom split view with an invisible but draggable divider
fileprivate class InvisibleDividerSplitView: NSSplitView {

    /// Real visual divider thickness (small gap)
    override var dividerThickness: CGFloat { 2.0 }

    /// No visible divider
    override func drawDivider(in rect: NSRect) { }

    /// How far UPWARD the clickable zone extends into the bottom of the DZ
    private let extendedHitZone: CGFloat = 12.0

    /// Expand hit testing upward into the bottom of the top subview
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard arrangedSubviews.count > 1 else {
            return super.hitTest(point)
        }

        let topFrame = arrangedSubviews[0].frame
        let dividerY = topFrame.maxY

        // Extended region from a bit above the divider down through the divider
        let extendedRect = NSRect(
            x: 0,
            y: dividerY - extendedHitZone,
            width: bounds.width,
            height: extendedHitZone + dividerThickness
        )

        if extendedRect.contains(point) {
            // Route events in this band to the split view so mouseDown sees them
            return self
        }

        return super.hitTest(point)
    }

    /// Cursor rect for feedback matches the extended hit zone
    override func resetCursorRects() {
        super.resetCursorRects()

        guard arrangedSubviews.count > 1 else { return }

        let topFrame = arrangedSubviews[0].frame
        let dividerY = topFrame.maxY

        let rect = NSRect(
            x: 0,
            y: dividerY - extendedHitZone,
            width: bounds.width,
            height: extendedHitZone + dividerThickness
        )

        addCursorRect(rect, cursor: .resizeUpDown)
    }

    /// Snap clicks in the extended zone onto the actual divider
    override func mouseDown(with event: NSEvent) {
        guard arrangedSubviews.count > 1,
              let window = self.window
        else {
            super.mouseDown(with: event)
            return
        }

        let pointInView = convert(event.locationInWindow, from: nil)
        let topFrame = arrangedSubviews[0].frame
        let dividerY = topFrame.maxY

        let dividerRect = NSRect(
            x: 0,
            y: dividerY,
            width: bounds.width,
            height: dividerThickness
        )

        let extendedRect = NSRect(
            x: 0,
            y: dividerY - extendedHitZone,
            width: bounds.width,
            height: extendedHitZone + dividerThickness
        )

        // If we're in the extended region but NOT in the real divider,
        // synthesize a click on the divider’s center line.
        if extendedRect.contains(pointInView) && !dividerRect.contains(pointInView) {

            let snappedPointInView = NSPoint(
                x: pointInView.x,
                y: dividerRect.midY
            )
            let snappedLocationInWindow = convert(snappedPointInView, to: nil)

            let snappedEvent = NSEvent.mouseEvent(
                with: event.type,
                location: snappedLocationInWindow,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: event.eventNumber,
                clickCount: event.clickCount,
                pressure: event.pressure
            )

            super.mouseDown(with: snappedEvent!)
        } else {
            super.mouseDown(with: event)
        }
    }
}

struct TopBottomSplitView<Top: View, Bottom: View>: NSViewRepresentable {
    let top: Top
    let bottom: Bottom
    let minTopHeight: CGFloat
    let minBottomHeight: CGFloat
    @Binding var topHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(
            minTopHeight: minTopHeight,
            minBottomHeight: minBottomHeight,
            topHeight: $topHeight
        )
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = InvisibleDividerSplitView()
        splitView.isVertical = false                    // horizontal split: top/bottom
        splitView.dividerStyle = .thin                  // style doesn't matter; we override drawing
        splitView.delegate = context.coordinator
        splitView.translatesAutoresizingMaskIntoConstraints = false

        let topHost = NSHostingView(rootView: top)
        let bottomHost = NSHostingView(rootView: bottom)

        splitView.addArrangedSubview(topHost)
        splitView.addArrangedSubview(bottomHost)

        // Initial divider position will be set in next layout pass
        DispatchQueue.main.async {
            let total = splitView.bounds.height
            guard total > 0 else { return }
            let maxTop = max(self.minTopHeight, total - self.minBottomHeight)
            let clamped = max(self.minTopHeight, min(self.topHeight, maxTop))
            splitView.setPosition(clamped, ofDividerAt: 0)
        }

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        if let topHost = splitView.arrangedSubviews.first as? NSHostingView<Top> {
            topHost.rootView = top
        }
        if let bottomHost = splitView.arrangedSubviews.last as? NSHostingView<Bottom> {
            bottomHost.rootView = bottom
        }
        // If you want, you can also drive divider from topHeight here.
    }

    class Coordinator: NSObject, NSSplitViewDelegate {
        let minTopHeight: CGFloat
        let minBottomHeight: CGFloat
        var topHeight: Binding<CGFloat>

        init(minTopHeight: CGFloat, minBottomHeight: CGFloat, topHeight: Binding<CGFloat>) {
            self.minTopHeight = minTopHeight
            self.minBottomHeight = minBottomHeight
            self.topHeight = topHeight
        }

        func splitView(_ splitView: NSSplitView,
                       constrainSplitPosition proposedPosition: CGFloat,
                       ofSubviewAt dividerIndex: Int) -> CGFloat {
            let total = splitView.bounds.height
            let maxTop = max(minTopHeight, total - minBottomHeight)
            let clamped = max(minTopHeight, min(proposedPosition, maxTop))
            topHeight.wrappedValue = clamped
            return clamped
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? NSSplitView,
                  splitView.subviews.count >= 1 else { return }
            let currentTop = splitView.subviews[0].frame.height
            topHeight.wrappedValue = currentTop
        }
    }
}

// MARK: - Footer Overlay

private struct FooterOverlay: View {
    @EnvironmentObject var state: AppState
    @StateObject private var footerViewModel = FooterViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if footerViewModel.shouldShowMessages(state.uiMessages) {
                UI_MessageArea()
                    .environmentObject(state)
                    .padding(.top, StyleConstants.footerTopPadding)
            }

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

    var body: some View {
        HStack(alignment: StyleConstants.footerStatusAlignment, spacing: 16) {
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
            .frame(minHeight: StyleConstants.footerStatusMinHeight, alignment: .top)

            Spacer()

            if footerViewModel.shouldShowProgress(files: state.files) {
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

            HStack(spacing: 8) {
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

// MARK: - Settings Revalidation

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
