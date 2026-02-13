//
//  UI_ScaleCropOptions.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/16/25.
//

import SwiftUI

struct UI_ScaleCropOptions: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.scaleExpanded) {
                VStack(alignment: .leading, spacing: StyleConstants.sectionSpacing) {

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scale").font(.headline)
                        Picker("", selection: $state.settings.scale) {
                            Text("No Scale (1:1)").tag(ScaleOption.oneToOne)
                            Text("Half (1/2)").tag(ScaleOption.half)
                            Text("Quarter (1/4)").tag(ScaleOption.quarter)
                        }
                        .labelsHidden()
                        .help("Downscale before encoding to reduce output resolution/bitrate.")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Text("Filename Suffix").font(.headline)
                            Text("Example: -HALF, -QUARTER")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        TextField("", text: $state.settings.scaleSuffix)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: state.settings.scale) { newVal in
                                let cur = state.settings.scaleSuffix.trimmingCharacters(in: .whitespaces)
                                let wasSuggested = cur.isEmpty || cur == "-HALF" || cur == "-QUARTER"
                                if wasSuggested {
                                    state.settings.scaleSuffix = suggestScaleSuffix(for: newVal)
                                }
                            }
                    }
                }
                .padding(StyleConstants.panelInsets)
                .padding(.top, StyleConstants.panelInsets.top)
            } label: {
                let inactive = (state.settings.scale == .oneToOne)
                             && state.settings.scaleSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Text("Scale & Crop")
                    .font(.headline)
                    .opacity(inactive ? 0.35 : 1.0)
            }
        }
    }

    private func suggestScaleSuffix(for s: ScaleOption) -> String {
        switch s {
        case .oneToOne: return ""
        case .half:     return "-HALF"
        case .quarter:  return "-QUARTER"
        }
    }
}
