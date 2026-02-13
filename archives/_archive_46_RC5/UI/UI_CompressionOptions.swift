import SwiftUI

struct UI_CompressionOptions: View {
    @EnvironmentObject var state: AppState
    @State private var prevCompressionSuffix: String? = nil

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.generalExpanded) {
                VStack(alignment: .leading, spacing: StyleConstants.sectionSpacing) {

                    HStack {
                        Toggle("No Changes", isOn: $state.settings.bypassHEVC)
                            .toggleStyle(.switch)
                            .help("Copy video exactly as-is, ignoring all processing options below.")
                            .onChange(of: state.settings.bypassHEVC) { on in
                                if on {
                                    if prevCompressionSuffix == nil {
                                        prevCompressionSuffix = state.settings.outputSuffix
                                    }
                                    state.settings.outputSuffix = ""
                                } else {
                                    let restore = (prevCompressionSuffix?.isEmpty == false) ? prevCompressionSuffix! : "-HEVC"
                                    state.settings.outputSuffix = restore
                                }
                            }
                            .onAppear {
                                if state.settings.bypassHEVC {
                                    if prevCompressionSuffix == nil { prevCompressionSuffix = state.settings.outputSuffix }
                                    state.settings.outputSuffix = ""
                                }
                            }
                        Spacer()
                    }

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text("Quality").font(.headline)
                                Text("(CRF \(state.settings.qualityCRF))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Smaller file").font(.caption)
                                Slider(
                                    value: Binding(
                                        get: {
                                            let crfMin = 14.0, crfMax = 30.0
                                            return (crfMin + crfMax) - Double(state.settings.qualityCRF)
                                        },
                                        set: {
                                            let crfMin = 14.0, crfMax = 30.0
                                            state.settings.qualityCRF = Int(((crfMin + crfMax) - $0).rounded())
                                        }
                                    ),
                                    in: 14.0...30.0, step: 1
                                )
                                Text("Best quality").font(.caption)
                            }
                            .help("Left = smaller file (higher CRF). Right = best quality (lower CRF).")
                        }
                        .frame(maxWidth: .infinity)

                        Spacer(minLength: 8)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("File Format").font(.headline)
                                .opacity(state.settings.bypassHEVC ? 0.35 : 1.0)
                            Picker("", selection: $state.settings.containerFormat) {
                                Text("QuickTime (.mov)").tag(ContainerFormat.mov)
                                Text("MP4 (.mp4)").tag(ContainerFormat.mp4)
                            }
                            .pickerStyle(.menu)
                            .frame(width: StyleConstants.containerPickerWidth)
                            .help("Choose output container format. MP4 is more universal for delivery.")
                            .disabled(state.settings.bypassHEVC)
                            .opacity(state.settings.bypassHEVC ? 0.35 : 1.0)
                            .onChange(of: state.settings.containerFormat) { newFormat in
                                if newFormat == .mp4 {
                                    let currentSuffix = state.settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if currentSuffix == "-HEVC" || currentSuffix == "-hevc" || currentSuffix.isEmpty {
                                        state.settings.outputSuffix = ""
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Text("Filename Suffix").font(.headline)
                            Text("Example: \(exampleOutputName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        TextField(state.settings.containerFormat == .mp4 ? "Optional for MP4" : "-HEVC",
                                  text: $state.settings.outputSuffix)
                            .textFieldStyle(.roundedBorder)
                            .help("Appends this to the output filename before the extension.")
                    }
                }
                .padding(StyleConstants.panelInsets)
                .padding(.top, StyleConstants.panelInsets.top)
            } label: {
                let inactive = state.settings.bypassHEVC
                            && state.settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Text("Compression")
                    .font(.headline)
                    .opacity(inactive ? 0.35 : 1.0)
            }
        }
    }

    private var exampleOutputName: String {
        let base = state.files.first?.url.deletingPathExtension().lastPathComponent ?? "myfile"
        let ext = state.settings.containerFormat.fileExtension
        let suffix = state.settings.outputSuffix.isEmpty ?
            (state.settings.containerFormat == .mp4 ? "" : "-HEVC") :
            state.settings.outputSuffix
        return "\(base)\(suffix).\(ext)"
    }
}
