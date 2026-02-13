import SwiftUI

struct UI_MainOptions: View {
    @EnvironmentObject var state: AppState

    // Remember previous suffix when user turns on Don’t Compress
    @State private var prevCompressionSuffix: String? = nil

    private enum C {
        static let panelInsets = EdgeInsets(top: 6, leading: 12, bottom: 2, trailing: 6)
    }

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.generalExpanded) {
                VStack(alignment: .leading, spacing: 12) {

                    // Don’t Compress (bypass HEVC path)
                    Toggle("Don't Compress", isOn: $state.settings.bypassHEVC)
                        .help("If no scaling or overlays are selected, video is copied without re-encoding; if scaling/overlays are active, video is re-encoded using the source codec (not HEVC).")
                        .onChange(of: state.settings.bypassHEVC) { on in
                            if on {
                                // Save current suffix and clear the box
                                if prevCompressionSuffix == nil {
                                    prevCompressionSuffix = state.settings.outputSuffix
                                }
                                state.settings.outputSuffix = ""
                            } else {
                                // Restore previous or default “-HEVC”
                                let restore = (prevCompressionSuffix?.isEmpty == false) ? prevCompressionSuffix! : "-HEVC"
                                state.settings.outputSuffix = restore
                            }
                        }
                        .onAppear {
                            // If Don’t Compress is already on at launch, clear the suffix and capture prior once.
                            if state.settings.bypassHEVC {
                                if prevCompressionSuffix == nil { prevCompressionSuffix = state.settings.outputSuffix }
                                state.settings.outputSuffix = ""
                            }
                        }

                    // Filename suffix (Compression)
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
                                    in: crfMin...crfMax, step: 1
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
                .padding(.top, C.panelInsets.top * 1.0)
            } label: {
                let inactive = state.settings.bypassHEVC
                            && state.settings.scale == .oneToOne
                            && state.settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Text("Compression & Resizing")
                    .font(.headline)
                    .opacity(inactive ? 0.35 : 1)
            }

        }
    }

    private var exampleOutputName: String {
        let base = state.files.first?.url.deletingPathExtension().lastPathComponent ?? "myfile"
        let ext  = state.files.first?.url.pathExtension.lowercased() ?? "mov"
        return "\(base)\(state.settings.outputSuffix).\(ext)"
    }
}
