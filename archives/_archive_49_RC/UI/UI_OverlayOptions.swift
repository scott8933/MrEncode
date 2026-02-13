//
//  UI_OverlayOptions.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/16/25.
//

import SwiftUI

struct UI_OverlayOptions: View {
    @EnvironmentObject var state: AppState

    @State private var uiTextColor: Color = .white
    @State private var uiBoxColor: Color  = Color.black.opacity(0.8)

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.overlaysExpanded) {
                VStack(alignment: .leading, spacing: StyleConstants.sectionSpacing) {

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Text Overlay").font(.headline)
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Text Color")
                            ColorPicker("", selection: $uiTextColor, supportsOpacity: true)
                                .labelsHidden()

                            Toggle("Text Box", isOn: $state.settings.overlayBoxEnabled)
                                .font(.body)

                            Text("Box Color")
                                .font(.body)
                                .opacity(state.settings.overlayBoxEnabled ? 1.0 : 0.5)

                            ColorPicker("", selection: $uiBoxColor, supportsOpacity: true)
                                .labelsHidden()
                                .disabled(!state.settings.overlayBoxEnabled)
                                .opacity(state.settings.overlayBoxEnabled ? 1.0 : 0.35)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    Divider()

                    HStack(alignment: .center, spacing: 24) {
                        Toggle("Frames", isOn: $state.settings.burnInFrames)
                        UI_PositionPicker(selection: $state.settings.burnInFramesPosition)
                            .frame(width: StyleConstants.overlayLabelWidth)
                            .disabled(!state.settings.burnInFrames)
                            .opacity(state.settings.burnInFrames ? 1.0 : 0.35)

                        Toggle("Timecode", isOn: $state.settings.burnInTimecode)
                        UI_PositionPicker(selection: $state.settings.burnInTimecodePosition)
                            .frame(width: StyleConstants.overlayLabelWidth)
                            .disabled(!state.settings.burnInTimecode)
                            .opacity(state.settings.burnInTimecode ? 1.0 : 0.35)

                        Toggle("Filename", isOn: $state.settings.burnInFilename)
                        UI_PositionPicker(selection: $state.settings.burnInFilenamePosition)
                            .frame(width: StyleConstants.overlayLabelWidth)
                            .disabled(!state.settings.burnInFilename)
                            .opacity(state.settings.burnInFilename ? 1.0 : 0.35)

                        Spacer(minLength: 0)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(StyleConstants.panelInsets)
                .padding(.top, StyleConstants.panelInsets.top)
            } label: {
                let inactive = !(state.settings.burnInFrames
                              || state.settings.burnInTimecode
                              || state.settings.burnInFilename)
                Text("Overlay Shot Info")
                    .font(.headline)
                    .opacity(inactive ? 0.35 : 1)
            }

        }
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
}
