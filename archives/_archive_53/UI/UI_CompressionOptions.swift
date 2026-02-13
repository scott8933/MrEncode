// =============================
// File: UI_CompressionOptions.swift
// =============================

import SwiftUI

struct UI_CompressionOptions: View {
    @EnvironmentObject var state: AppState
    
    private let itemGap: CGFloat = 2
    private var groupGap: CGFloat = 30
    private let modePickerWidth: CGFloat = 220
    private let qualitySliderMaxWidth: CGFloat = 210

    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header (click toggles)
            Button {
                withAnimation(.easeInOut(duration: StyleConstants.expandAnimationDuration)) {
                    state.settings.generalExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: state.settings.generalExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)

                    Text("Compression")
                        .font(.headline)
                        .opacity(inactive ? 0.35 : 1.0)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if state.settings.generalExpanded {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: StyleConstants.sectionSpacing) {

                    // MARK: Codec + File Format
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {

                            HStack(spacing: itemGap) {
                                Text("Codec")
                                    .font(.headline)
                                    .fixedSize(horizontal: true, vertical: false)

                                Picker("", selection: $state.settings.codec) {
                                    Text("H.265 (HEVC)").tag(VideoCodec.hevc)
                                    Text("H.264 (AVC)").tag(VideoCodec.h264)
                                    Text("No Recompression").tag(VideoCodec.bypass)
                                }
                                .pickerStyle(.menu)
                                .onChange(of: state.settings.codec) { newCodec in
                                    applyCodecSelectionToSuffix(newCodec)
                                }
                            }

                            Color.clear.frame(width: groupGap)

                            HStack(spacing: itemGap) {
                                Text("File Format")
                                    .font(.headline)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .opacity(isBypass ? 0.35 : 1.0)

                                Picker("", selection: $state.settings.containerFormat) {
                                    Text("QuickTime (.mov)").tag(ContainerFormat.mov)
                                    Text("MP4 (.mp4)").tag(ContainerFormat.mp4)
                                }
                                .pickerStyle(.menu)
                                .disabled(isBypass)
                                .opacity(isBypass ? 0.35 : 1.0)
                                .onChange(of: state.settings.containerFormat) { newFormat in
                                    adaptSuffixForContainerAndCodec(container: newFormat, codec: state.settings.codec)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // MARK: Quality (CRF)
                    if !isBypass {
                        GridRow {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text("Quality").font(.headline)
                                    Text("(CRF \(state.settings.qualityCRF)) – \(qualityCodecLabel)")
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
                                    .frame(maxWidth: qualitySliderMaxWidth)
                                    Text("Best quality").font(.caption)
                                }
                                .help("Left = smaller file (higher CRF). Right = best quality (lower CRF).")
                            }
                            .gridCellColumns(5)
                        }
                        .transition(.opacity) // fade quality in/out
                    }

                    // MARK: Filename Suffix
                    GridRow {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                Text("Filename Suffix").font(.headline)
                                Text("Example: \(exampleOutputName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            TextField(suffixPlaceholder, text: $state.settings.outputSuffix)
                                .textFieldStyle(.roundedBorder)
                                .help("Appends this to the output filename before the extension.")
                        }
                        .gridCellColumns(5)
                    }
                }
                .padding(StyleConstants.panelInsets)
                .padding(.top, StyleConstants.panelInsets.top)
                .transition(.opacity) // fade entire panel content in/out
            }
        }
        // Animate both: expand height + quality show/hide
        .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration),
                   value: state.settings.generalExpanded)
        .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration),
                   value: isBypass)
    }


    
    // MARK: Helpers
    
    private func applyCodecSelectionToSuffix(_ codec: VideoCodec) {
        switch codec {
        case .bypass:
            // Pass-through: clear
            state.settings.outputSuffix = ""

        case .hevc:
            state.settings.outputSuffix = (state.settings.containerFormat == .mp4)
                ? ""
                : applySuggestedSeparator("HEVC", settings: state.settings)

        case .h264:
            state.settings.outputSuffix = (state.settings.containerFormat == .mp4)
                ? ""
                : applySuggestedSeparator("H264", settings: state.settings)
        }
    }


    // MARK: Derived UI flags/text

    private var isBypass: Bool { state.settings.codec == .bypass }
    private var inactive: Bool { !state.settings.generalExpanded }
    private var qualityCodecLabel: String {
        switch state.settings.codec {
        case .hevc: return "H.265"
        case .h264: return "H.264"
        case .bypass: return "—"
        }
    }

    private var suffixPlaceholder: String {
        if isBypass { return "Optional (No Recompression)" }
        switch state.settings.codec {
        case .hevc:
            return state.settings.containerFormat == .mp4
                ? "Optional for MP4"
                : applySuggestedSeparator("HEVC", settings: state.settings)
        case .h264:
            return state.settings.containerFormat == .mp4
                ? "Optional for MP4"
                : applySuggestedSeparator("H264", settings: state.settings)
        case .bypass:
            return "Optional (No Recompression)"
        }
    }

    private var exampleOutputName: String {
        let base = state.files.first?.url.deletingPathExtension().lastPathComponent ?? "myfile"
        let ext = state.settings.containerFormat.fileExtension

        // If user left suffix empty, show logical default preview for current mode
        let shownSuffix: String = {
            if isBypass { return "" }
            let current = state.settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty {
                switch state.settings.codec {
                case .hevc:
                    state.settings.outputSuffix = (state.settings.containerFormat == .mp4)
                        ? ""
                        : applySuggestedSeparator("HEVC", settings: state.settings)

                case .h264:
                    state.settings.outputSuffix = (state.settings.containerFormat == .mp4)
                        ? ""
                        : applySuggestedSeparator("H264", settings: state.settings)
                case .bypass: return ""
                }
            }
            return current
        }()

        return "\(base)\(shownSuffix).\(ext)"
    }

    // MARK: Mode application

    func applyMode(_ newMode: VideoCodec, initializing: Bool = false) {
        // New rule: dropdown change always wins.
        // - bypass: clear
        // - hevc/h264: reset to default for that codec (container-dependent)
        switch newMode {
        case .bypass:
            state.settings.outputSuffix = ""

        case .hevc:
            state.settings.outputSuffix = (state.settings.containerFormat == .mp4)
                ? ""
                : applySuggestedSeparator("HEVC", settings: state.settings)

        case .h264:
            state.settings.outputSuffix = (state.settings.containerFormat == .mp4)
                ? ""
                : applySuggestedSeparator("H264", settings: state.settings)
        }
    }

    private func adaptSuffixForContainerAndCodec(container: ContainerFormat, codec: VideoCodec) {
        // New rule: container dropdown change also resets suffix appropriately.
        switch codec {
        case .bypass:
            state.settings.outputSuffix = ""
        case .hevc:
            state.settings.outputSuffix = (state.settings.containerFormat == .mp4)
                ? ""
                : applySuggestedSeparator("HEVC", settings: state.settings)

        case .h264:
            state.settings.outputSuffix = (state.settings.containerFormat == .mp4)
                ? ""
                : applySuggestedSeparator("H264", settings: state.settings)
        }
    }

}





/*
 
 // Preview in Xcode
 // commented out, its typically faster to just compile the app
 
fileprivate extension String {
    func equalsCaseInsensitive(_ other: String) -> Bool {
        self.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(other) == .orderedSame
    }
}



#Preview("Compression Options") {
    UI_CompressionOptions()
        .environmentObject(AppState.preview)
        .frame(width: 640)
        .padding()
}
 
*/
