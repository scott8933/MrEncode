// =============================
// File: UI_CompressionOptions.swift
// =============================

import SwiftUI

struct UI_CompressionOptions: View {
    @EnvironmentObject var state: AppState
    
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }
    
    private let itemGap: CGFloat = 2
    private var groupGap: CGFloat = 30
    private let modePickerWidth: CGFloat = 220
    private let qualitySliderMaxWidth: CGFloat = 400

    
    var body: some View {
        let isExpanded = state.settings.generalExpanded
        let isModified = state.isPanelModified(.compression)

        VStack(alignment: .leading, spacing: 0) {

            Button {
                withAnimation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration)) {
                    state.settings.generalExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(C.textSecondary)
                        .frame(width: 14, height: 14)

                    Text("Compression")
                        .font(.headline)
                        .foregroundColor(
                            C.panelHeaderLabel(isExpanded: isExpanded, isModified: isModified)
                        )

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if state.settings.generalExpanded {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: StyleConstants.Spacing.sectionSpacing) {

                    // MARK: Codec + File Format
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {

                            HStack(spacing: itemGap) {
                                Text("Codec")
                                    .font(.headline)
                                    .fixedSize(horizontal: true, vertical: false)

                                Picker("", selection: $state.settings.codec) {
                                    Text("H.265 4:2:2 (Highest Quality)").tag(VideoCodec.hevc422)
                                    Text("H.265 4:2:0 (More Compatible)").tag(VideoCodec.hevc420)
                                    Text("H.264 (Most Compatible)").tag(VideoCodec.h264)
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

                    // MARK: Quality (stored as CRF for preset compatibility)
                    if !isBypass {
                        GridRow {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text("Quality").font(.headline)
                                    Text("\(qualityPercent)% – \(qualityCodecLabel)")
                                        .font(.subheadline)
                                        .foregroundColor(C.textSecondary)
                                }

                                HStack {
                                    Text("Lower").font(.caption)
                                    Slider(
                                        value: Binding(
                                            get: { Double(qualityPercent) },
                                            set: { newValue in
                                                let clamped = min(max(Int(newValue.rounded()), 0), 100)
                                                state.settings.qualityCRF = crfFromQualityPercent(clamped)
                                            }
                                        ),
                                        in: 0.0...100.0,
                                        step: 1.0
                                    )
                                    .frame(maxWidth: qualitySliderMaxWidth)
                                    Text("Higher").font(.caption)
                                }
                                .help("Higher = better quality.")
                            }
                            .gridCellColumns(5)
                        }
                        .transition(.opacity)
                    }

                    // MARK: Filename Suffix
                    GridRow {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                Text("Filename Suffix").font(.headline)
                                Text("Example: \(exampleOutputName)")
                                    .font(.caption)
                                    .foregroundColor(C.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            TextField(suffixPlaceholder, text: $state.settings.outputSuffix)
                                .panelTextFieldStyle(C)
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
        .fixedSize(horizontal: false, vertical: true)
        // Animate both: expand height + quality show/hide
        .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration),
                   value: state.settings.generalExpanded)
        .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration),
                   value: isBypass)
    }


    
    // MARK: Helpers
    
    private func applyCodecSelectionToSuffix(_ codec: VideoCodec) {
        switch codec {
        case .bypass:
            // Pass-through: clear
            state.settings.outputSuffix = ""

        case .hevc420, .hevc422:
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
        case .hevc422, .hevc420: return "H.265"
        case .h264: return "H.264"
        case .bypass: return "—"
        }
    }

    private var suffixPlaceholder: String {
        if isBypass { return "Optional (No Recompression)" }

        switch state.settings.codec {
        case .hevc422, .hevc420:
            return (state.settings.containerFormat == .mp4)
                ? "Optional for MP4"
                : applySuggestedSeparator("HEVC", settings: state.settings)

        case .h264:
            return (state.settings.containerFormat == .mp4)
                ? "Optional for MP4"
                : applySuggestedSeparator("H264", settings: state.settings)

        case .bypass:
            return "Optional (No Recompression)"
        }
    }


    private var exampleOutputName: String {
        let base = state.files.first?.url.deletingPathExtension().lastPathComponent ?? "myfile"
        let ext  = state.settings.containerFormat.fileExtension

        let current = state.settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines)

        let suggestedToken: String = {
            if state.settings.bypassHEVC { return "" }

            switch state.settings.codec {
            case .hevc420, .hevc422:
                return (state.settings.containerFormat == .mp4) ? "" : "HEVC"
            case .h264:
                return (state.settings.containerFormat == .mp4) ? "" : "H264"
            case .bypass:
                return ""
            }
        }()

        let shownSuffix: String
        if state.settings.bypassHEVC {
            shownSuffix = ""
        } else if !current.isEmpty {
            shownSuffix = current
        } else if suggestedToken.isEmpty {
            shownSuffix = ""
        } else {
            shownSuffix = applySuggestedSeparator(suggestedToken, settings: state.settings)
        }

        return "\(base)\(shownSuffix).\(ext)"
    }


    
    private var qualityPercent: Int {
        // Map stored CRF [14...30] => Quality [100...0], then flip so higher=better.
        // CRF 14 = best, 30 = smallest file.
        let crfMin = 14
        let crfMax = 30
        let crf = min(max(state.settings.qualityCRF, crfMin), crfMax)

        let t = Double(crf - crfMin) / Double(crfMax - crfMin) // 0(best)..1(worst)
        let q = 1.0 - t                                         // 1(best)..0(worst)
        return Int((q * 100.0).rounded())
    }

    private func crfFromQualityPercent(_ percent: Int) -> Int {
        let crfMin = 14
        let crfMax = 30
        let q = Double(min(max(percent, 0), 100)) / 100.0       // 0..1 (higher better)
        let t = 1.0 - q                                         // 1..0 (higher worse)
        let crf = Double(crfMin) + t * Double(crfMax - crfMin)
        return Int(crf.rounded())
    }


    // MARK: Mode application

    func applyMode(_ newMode: VideoCodec, initializing: Bool = false) {
        switch newMode {
        case .bypass:
            state.settings.outputSuffix = ""

        case .hevc420, .hevc422:
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
        switch codec {
        case .bypass:
            state.settings.outputSuffix = ""

        case .hevc420, .hevc422:
            state.settings.outputSuffix = (container == .mp4)
                ? ""
                : applySuggestedSeparator("HEVC", settings: state.settings)

        case .h264:
            state.settings.outputSuffix = (container == .mp4)
                ? ""
                : applySuggestedSeparator("H264", settings: state.settings)
        }
    }


}
