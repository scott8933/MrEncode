// =============================
// File: UI_ActionBar.swift
// =============================

import SwiftUI

struct UI_CompressionOptions: View {
    @EnvironmentObject var state: AppState

    // Remember last non-bypass suffix so we can restore it
    @State private var prevCompressionSuffix: String? = nil

    var body: some View {
        DisclosureGroup(isExpanded: $state.settings.generalExpanded) {
            VStack(alignment: .leading, spacing: StyleConstants.sectionSpacing) {

                // MARK: Codec Mode (3-state)
                HStack(spacing: 12) {
                    Text("Codec").font(.headline)

                    Picker("", selection: $state.settings.codec) {
                        Text("H.265").tag(VideoCodec.hevc)
                        Text("H.264").tag(VideoCodec.h264)
                        Text("No Recompression").tag(VideoCodec.bypass)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 340)
                    .onChange(of: state.settings.codec) { newMode in
                        applyMode(newMode)
                    }
                    .onAppear {
                        applyMode(state.settings.codec, initializing: true)
                    }


                    Spacer()
                }

                // MARK: Quality (CRF – same direction/range for both codecs)
                HStack(spacing: 20) {
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
                            .disabled(isBypass)
                            Text("Best quality").font(.caption)
                        }
                        .help("Left = smaller file (higher CRF). Right = best quality (lower CRF).")
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(isBypass ? 0.35 : 1.0)

                    Spacer(minLength: 8)

                    // MARK: Container format
                    VStack(alignment: .leading, spacing: 8) {
                        Text("File Format").font(.headline)
                            .opacity(isBypass ? 0.35 : 1.0)
                        Picker("", selection: $state.settings.containerFormat) {
                            Text("QuickTime (.mov)").tag(ContainerFormat.mov)
                            Text("MP4 (.mp4)").tag(ContainerFormat.mp4)
                        }
                        .pickerStyle(.menu)
                        .frame(width: StyleConstants.containerPickerWidth)
                        .help("Choose output container format. MP4 is more universal for delivery.")
                        .disabled(isBypass)
                        .opacity(isBypass ? 0.35 : 1.0)
                        .onChange(of: state.settings.containerFormat) { newFormat in
                            adaptSuffixForContainerAndCodec(container: newFormat, codec: state.settings.codec)
                        }
                    }
                }

                // MARK: Filename Suffix
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
                        .disabled(isBypass)
                        .opacity(isBypass ? 0.35 : 1.0)
                }
            }
            .padding(StyleConstants.panelInsets)
            .padding(.top, StyleConstants.panelInsets.top)
        } label: {
            let inactive = isBypass && state.settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Text("Compression")
                .font(.headline)
                .opacity(inactive ? 0.35 : 1.0)
        }
    }

    // MARK: Derived UI flags/text

    private var isBypass: Bool { state.settings.codec == .bypass }
    private var qualityCodecLabel: String {
        switch state.settings.codec {
        case .hevc: return "H.265"
        case .h264: return "H.264"
        case .bypass: return "—"
        }
    }

    private var suffixPlaceholder: String {
        if isBypass { return "Disabled (No Recompression)" }
        switch state.settings.codec {
        case .hevc:
            return state.settings.containerFormat == .mp4 ? "Optional for MP4" : "-HEVC"
        case .h264:
            return state.settings.containerFormat == .mp4 ? "Optional for MP4" : "-H264"
        case .bypass:
            return "Disabled (No Recompression)"
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
                case .hevc: return state.settings.containerFormat == .mp4 ? "" : "-HEVC"
                case .h264: return state.settings.containerFormat == .mp4 ? "" : "-H264"
                case .bypass: return ""
                }
            }
            return current
        }()

        return "\(base)\(shownSuffix).\(ext)"
    }

    // MARK: Mode application

    private func applyMode(_ newMode: VideoCodec, initializing: Bool = false) {
        switch newMode {
        case .bypass:
            if !initializing, prevCompressionSuffix == nil {
                prevCompressionSuffix = state.settings.outputSuffix
            }
            state.settings.outputSuffix = ""
        case .hevc, .h264:
            // Restore prior suffix if we had one; otherwise pick a logical default
            let current = state.settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty {
                // Default suffix for .mov, blank for .mp4
                if state.settings.containerFormat == .mp4 {
                    state.settings.outputSuffix = ""
                } else {
                    state.settings.outputSuffix = (newMode == .hevc) ? "-HEVC" : "-H264"
                }
            }
        }
        if newMode != .bypass, let prev = prevCompressionSuffix, !prev.isEmpty, state.settings.outputSuffix.isEmpty {
            state.settings.outputSuffix = prev
        }
        if newMode != .bypass { prevCompressionSuffix = nil }
        adaptSuffixForContainerAndCodec(container: state.settings.containerFormat, codec: newMode)
    }

    private func adaptSuffixForContainerAndCodec(container: ContainerFormat, codec: VideoCodec) {
        guard codec != .bypass else { return }
        let current = state.settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDefaultish = current.isEmpty
            || current.equalsCaseInsensitive("-HEVC")
            || current.equalsCaseInsensitive("-H265")
            || current.equalsCaseInsensitive("-H264")

        if container == .mp4 {
            if isDefaultish { state.settings.outputSuffix = "" }
        } else {
            if isDefaultish {
                state.settings.outputSuffix = (codec == .h264) ? "-H264" : "-HEVC"
            }
        }
    }
}

fileprivate extension String {
    func equalsCaseInsensitive(_ other: String) -> Bool {
        self.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(other) == .orderedSame
    }
}
