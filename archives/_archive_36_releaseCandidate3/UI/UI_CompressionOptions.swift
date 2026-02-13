import SwiftUI

struct UI_CompressionOptions: View {
    @EnvironmentObject var state: AppState

    // Remember previous suffix when user turns on Don't Recompress
    @State private var prevCompressionSuffix: String? = nil

    private enum C {
        // Matches your established panel rhythm
        static let panelInsets = EdgeInsets(top: 6, leading: 12, bottom: 2, trailing: 6)
    }

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.generalExpanded) {
                VStack(alignment: .leading, spacing: 12) {

                    // No Changes at top left (first option)
                    HStack {
                        Toggle("No Changes", isOn: $state.settings.bypassHEVC)
                            .toggleStyle(.switch)
                            .help("Copy video exactly as-is, ignoring all processing options below.")
                            .onChange(of: state.settings.bypassHEVC) { on in
                                if on {
                                    // Save current suffix and clear the box
                                    if prevCompressionSuffix == nil {
                                        prevCompressionSuffix = state.settings.outputSuffix
                                    }
                                    state.settings.outputSuffix = ""
                                } else {
                                    // Restore previous or default "-HEVC"
                                    let restore = (prevCompressionSuffix?.isEmpty == false) ? prevCompressionSuffix! : "-HEVC"
                                    state.settings.outputSuffix = restore
                                }
                            }
                            .onAppear {
                                // If No Changes is already on at launch, clear the suffix and capture prior once.
                                if state.settings.bypassHEVC {
                                    if prevCompressionSuffix == nil { prevCompressionSuffix = state.settings.outputSuffix }
                                    state.settings.outputSuffix = ""
                                }
                            }
                        
                        Spacer()
                    }

                    // Quality + container in horizontal layout
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

                                // Inverted CRF: lower CRF (higher quality) is to the RIGHT
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

                        Spacer(minLength: 8)

                        // Container format picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("File Format").font(.headline)
                                .opacity(state.settings.bypassHEVC ? 0.35 : 1.0)
                            Picker("", selection: $state.settings.containerFormat) {
                                Text("QuickTime (.mov)").tag(ContainerFormat.mov)
                                Text("MP4 (.mp4)").tag(ContainerFormat.mp4)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 160)
                            .help("Choose output container format. MP4 is more universal for delivery.")
                            .disabled(state.settings.bypassHEVC)
                            .opacity(state.settings.bypassHEVC ? 0.35 : 1.0)
                            .onChange(of: state.settings.containerFormat) { newFormat in
                                // Clear filename suffix when switching to MP4 (unless user has customized it)
                                if newFormat == .mp4 {
                                    let currentSuffix = state.settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
                                    // Only clear if it's a default/standard suffix
                                    if currentSuffix == "-HEVC" || currentSuffix == "-hevc" || currentSuffix.isEmpty {
                                        state.settings.outputSuffix = ""
                                    }
                                }
                            }
                        }
                    }

                    // Filename suffix at the bottom
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
                .padding(C.panelInsets)
                .padding(.top, C.panelInsets.top) // +100% header gap (double the base)
            } label: {
                // Inactive when pass-through AND no compression suffix
                let inactive = state.settings.bypassHEVC
                            && state.settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Text("Compression")
                    .font(.headline)
                    .opacity(inactive ? 0.35 : 1.0) // saved preference
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
