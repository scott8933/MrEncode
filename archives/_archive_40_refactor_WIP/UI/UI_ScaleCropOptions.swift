import SwiftUI

struct UI_ScaleCropOptions: View {
    @EnvironmentObject var state: AppState

    private enum C {
        static let panelInsets = EdgeInsets(top: 6, leading: 12, bottom: 2, trailing: 6)
    }

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.scaleExpanded) {
                VStack(alignment: .leading, spacing: 12) {

                    // Scale dropdown (kept as popup for future explicit size fields)
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

                    // Filename Suffix (blank on No Scale; suggest for 1/2 and 1/4)
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
                                // Suggest only if the user hasn't customized it
                                let cur = state.settings.scaleSuffix.trimmingCharacters(in: .whitespaces)
                                let wasSuggested = cur.isEmpty || cur == "-HALF" || cur == "-QUARTER"
                                if wasSuggested {
                                    state.settings.scaleSuffix = suggestScaleSuffix(for: newVal)
                                }
                            }
                    }

                    // (Crop fields will live here later)
                }
                .padding(C.panelInsets)
                .padding(.top, C.panelInsets.top) // +100% header gap
            } label: {
                // Inactive when 1:1 AND no scale suffix
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
        case .oneToOne: return ""          // blank when no scale
        case .half:     return "-HALF"     // common editorial/VFX convention
        case .quarter:  return "-QUARTER"
        }
    }
}
