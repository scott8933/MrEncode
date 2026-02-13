//
//  UI_OverlayOptions.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/16/25.
//

import SwiftUI

struct UI_OverlayOptions: View {
    @EnvironmentObject var state: AppState

    @State private var uiTextColor: Color = .white
    @State private var uiBoxColor: Color  = Color.black.opacity(0.8)

    // Match Compression / Scale&Crop layout numbers (hardcoded for now)
    private let itemGap: CGFloat = 2
    private let groupGap: CGFloat = 30
    private let positionPickerWidth: CGFloat = 60   // tight width for the 3×3 grid
    private let burnInGroupGap: CGFloat = 12        // separate from Text Overlay groupGap
    private let checkToLabelGap: CGFloat = 8        // Only in the grid selectors
    private let labelToGridGap: CGFloat = 10        // Only in the grid selectors

    var body: some View {
        let inactive = !(state.settings.burnInFrames
                      || state.settings.burnInTimecode
                      || state.settings.burnInFilename)

        VStack(alignment: .leading, spacing: 0) {

            // Header (match CompressionOptions)
            Button {
                withAnimation(.easeInOut(duration: StyleConstants.expandAnimationDuration)) {
                    state.settings.overlaysExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: state.settings.overlaysExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)

                    let dimHeader = !state.settings.overlaysExpanded && inactive

                    Text("Overlay Shot Info")
                        .font(.headline)
                        .opacity(dimHeader ? 0.35 : 1.0)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if state.settings.overlaysExpanded {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: StyleConstants.sectionSpacing) {

                    // MARK: Text Overlay header
                    GridRow {
                        Text("Text Overlay")
                            .font(.headline)
                            .gridCellColumns(5)
                    }

                    // MARK: Text Overlay controls (consolidated Text Box + Box Color)
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {

                            HStack(alignment: .center, spacing: itemGap) {
                                Text("Text Color")
                                    .fixedSize(horizontal: true, vertical: false)

                                ColorPicker("", selection: $uiTextColor, supportsOpacity: true)
                                    .labelsHidden()

                                Color.clear.frame(width: groupGap)

                                Toggle("Text Box", isOn: $state.settings.overlayBoxEnabled)
                                    .font(.body)
                                    .fixedSize(horizontal: true, vertical: false)

                                // Box color picker (implied; no label)
                                ColorPicker("", selection: $uiBoxColor, supportsOpacity: true)
                                    .labelsHidden()
                                    .disabled(!state.settings.overlayBoxEnabled)
                                    .opacity(state.settings.overlayBoxEnabled ? 1.0 : 0.20)
                            }
                            .fixedSize(horizontal: true, vertical: false)

                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // Divider between sections
                    GridRow {
                        Divider().gridCellColumns(5)
                    }

                    // MARK: Burn-in options (Frames / Timecode / Filename)
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {
                            burnInGroup(title: "Frames",
                                        isOn: $state.settings.burnInFrames,
                                        pos: $state.settings.burnInFramesPosition)

                            fixedGap(burnInGroupGap)

                            burnInGroup(title: "Timecode",
                                        isOn: $state.settings.burnInTimecode,
                                        pos: $state.settings.burnInTimecodePosition)

                            fixedGap(burnInGroupGap)

                            burnInGroup(title: "Filename",
                                        isOn: $state.settings.burnInFilename,
                                        pos: $state.settings.burnInFilenamePosition)

                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }
                }
                .padding(StyleConstants.panelInsets)
                .padding(.top, StyleConstants.panelInsets.top) // base + extra top padding rule
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration),
                   value: state.settings.overlaysExpanded)
        .onAppear {
            uiTextColor = UI_ColorFromHex(state.settings.overlayTextColorHex,
                                          alpha: state.settings.overlayTextColorAlpha)
            uiBoxColor  = UI_ColorFromHex(state.settings.overlayBoxColorHex,
                                          alpha: state.settings.overlayBoxColorAlpha)
        }
        .onChange(of: uiTextColor) { newValue in
            if let rgba = UI_RGBA(newValue) {
                state.settings.overlayTextColorHex   = UI_HexRGB(rgba.r, rgba.g, rgba.b)
                state.settings.overlayTextColorAlpha = rgba.a
            }
        }
        .onChange(of: uiBoxColor) { newValue in
            if let rgba = UI_RGBA(newValue) {
                state.settings.overlayBoxColorHex   = UI_HexRGB(rgba.r, rgba.g, rgba.b)
                state.settings.overlayBoxColorAlpha = rgba.a
            }
        }
    }

    
    
    // MARK: Helpers
    
    private func burnInGroup(
        title: String,
        isOn: Binding<Bool>,
        pos: Binding<BurnInPosition>
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {

            Toggle("", isOn: isOn)
                .labelsHidden()

            Spacer().frame(width: checkToLabelGap)

            Text(title)
                .font(.body)
                .fixedSize(horizontal: true, vertical: false)

            // Keep the “label-to-grid” spacing consistent even when hidden:
            Spacer().frame(width: labelToGridGap)

            if isOn.wrappedValue {
                UI_PositionPicker(selection: pos)
                    .frame(width: positionPickerWidth, alignment: .leading)
            } else {
                // Preserve layout footprint so inter-group gaps stay identical
                Color.clear
                    .frame(width: positionPickerWidth, height: 1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    
    @ViewBuilder
    private func fixedGap(_ w: CGFloat) -> some View {
        Color.clear
            .frame(width: w, height: 1)
            .fixedSize()
    }



}
