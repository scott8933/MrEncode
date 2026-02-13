import SwiftUI

struct UI_MainOptions: View {
    @EnvironmentObject var state: AppState

    private enum C {
        static let panelInsets = EdgeInsets(top: 6, leading: 6, bottom: 2, trailing: 6)
    }

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.mainExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    // Filename suffix
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Text("Filename Suffix").font(.headline)
                            Text("Example: \(exampleOutputName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        TextField("-HEVC", text: $state.settings.outputSuffix)
                            .textFieldStyle(.roundedBorder)
                            .help("Appends this to the output filename before the extension.")
                    }

                    // Quality + Scale row
                    HStack(spacing: 20) {
                        // Quality (CRF) inverted slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text("Quality").font(.headline)
                                Text("(CRF \(state.settings.qualityCRF))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Smaller file").font(.caption).foregroundColor(.primary)
                                let crfMin = 14.0, crfMax = 30.0, crfSum = crfMin + crfMax
                                Slider(
                                    value: Binding(
                                        get: { crfSum - Double(state.settings.qualityCRF) },
                                        set: { state.settings.qualityCRF = Int((crfSum - $0).rounded()) }
                                    ),
                                    in: crfMin...crfMax,
                                    step: 1
                                )
                                Text("Best quality").font(.caption).foregroundColor(.primary)
                            }
                            .help("Left = smaller file (higher CRF). Right = best quality (lower CRF).")
                        }
                        .frame(maxWidth: .infinity)

                        Divider().frame(height: 48)

                        // Scale
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Scale").font(.headline)
                            Picker("Scale", selection: $state.settings.scale) {
                                ForEach(ScaleOption.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                            .help("Downscale before encoding to reduce output resolution/bitrate.")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(C.panelInsets)
            } label: {
                Text("General")
            }
        }
    }

    private var exampleOutputName: String {
        let base = state.files.first?.url.deletingPathExtension().lastPathComponent ?? "myfile"
        let ext  = state.files.first?.url.pathExtension.lowercased() ?? "mov"
        return "\(base)\(state.settings.outputSuffix).\(ext)"
    }
}
