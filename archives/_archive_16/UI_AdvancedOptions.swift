//
//  UI.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/8/25.
//


import SwiftUI

struct UI_AdvancedOptions: View {
    @EnvironmentObject var state: AppState

    @State private var uiTextColor: Color = .white
    @State private var uiBoxColor: Color  = Color.black.opacity(0.8)

    private enum C {
        static let pickerWidth: CGFloat = 240
        static let labelWidth: CGFloat = 90
        static let panelInsets = EdgeInsets(top: 6, leading: 6, bottom: 2, trailing: 6)
    }

    private static let nclcOptions: [String] = [
        "No Change",
        "1-1-1 (BT.709)",
        "1-13-1 (sRGB)",
        "9-16-9 (BT.2020)",
        "12-16-1 (P3-D65)",
        "12-13-1 (DisplayP3)",
        "6-6-6 (Rec.601 NTSC)",
        "5-6-5 (Rec.601 PAL)",
        "9-1-9 (BT.2020 SDR)",
        "9-14-9 (BT.2020 SDR BT.1361)",
        "12-1-1 (P3-D65 SDR)",
        "12-18-1 (P3-D65 HLG)",
        "9-18-9 (BT.2020 HLG)",
        "9-16-10 (BT.2020 PQ CL)",
        "1-4-1 (BT.709 γ2.2)",
        "1-5-1 (BT.709 γ2.8)"
    ]

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.advancedExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    // NCLC
                    UI_LabeledField("NCLC Tagging", width: C.labelWidth, fills: false) {
                        Picker("", selection: $state.settings.nclcTag) {
                            ForEach(Self.nclcOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: C.pickerWidth, alignment: .leading)
                    }

                    Divider()

                    // Text Overlay appearance
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

                    // Burn-ins
                    HStack(alignment: .center, spacing: 24) {
                        Toggle("Frames", isOn: $state.settings.burnInFrames)
                        UI_PositionPicker(selection: $state.settings.burnInFramesPosition)
                            .frame(width: 66)
                            .disabled(!state.settings.burnInFrames)
                            .opacity(state.settings.burnInFrames ? 1.0 : 0.35)

                        Toggle("Timecode", isOn: $state.settings.burnInTimecode)
                        UI_PositionPicker(selection: $state.settings.burnInTimecodePosition)
                            .frame(width: 66)
                            .disabled(!state.settings.burnInTimecode)
                            .opacity(state.settings.burnInTimecode ? 1.0 : 0.35)

                        Toggle("Filename", isOn: $state.settings.burnInFilename)
                        UI_PositionPicker(selection: $state.settings.burnInFilenamePosition)
                            .frame(width: 66)
                            .disabled(!state.settings.burnInFilename)
                            .opacity(state.settings.burnInFilename ? 1.0 : 0.35)

                        Spacer(minLength: 0)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(C.panelInsets)
            } label: {
                Text("Advanced Options").font(.headline)
            }
        }
        // Color sync with Settings
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
