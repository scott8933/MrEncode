//
//  UI_OverlayOptions.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/16/25.
//

import SwiftUI

struct UI_OverlayOptions: View {
    @EnvironmentObject var state: AppState
    
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    @State private var uiTextColor: Color = .white
    @State private var uiBoxColor: Color  = Color.black.opacity(0.8)

    // Match Compression / Scale&Crop layout numbers (hardcoded for now)
    private let itemGap: CGFloat = 2
    private let groupGap: CGFloat = 30
    private let positionPickerWidth: CGFloat = 60   // tight width for the 3×3 grid
    private let burnInGroupGap: CGFloat = 12        // separate from Text Overlay groupGap
    private let checkToLabelGap: CGFloat = 8        // Only in the grid selectors
    private let labelToGridGap: CGFloat = 10        // Only in the grid selectors
    private let overlaySuffixPlaceholder = "Auto"


    var body: some View {
        let isExpanded = state.settings.overlaysExpanded
        let isModified = state.isPanelModified(.overlays)

        VStack(alignment: .leading, spacing: 0) {

            Button {
                withAnimation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration)) {
                    state.settings.overlaysExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(C.textSecondary)
                        .frame(width: 14, height: 14)

                    Text("Overlay Shot Info")
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
            if state.settings.overlaysExpanded {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: StyleConstants.Spacing.sectionSpacing) {

                    // MARK: Text Overlay header
                    GridRow {
                        Text("Text Overlay")
                            .font(.headline)
                            .gridCellColumns(5)
                    }

                    // MARK: Text Overlay controls (consolidated Text Box + Box Color)
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {

                            HStack(alignment: .center, spacing: itemGap) {
                                Text("Text Color")
                                    .fixedSize(horizontal: true, vertical: false)

                                ColorPicker("", selection: $uiTextColor, supportsOpacity: true)
                                    .labelsHidden()

                                Color.clear.frame(width: groupGap)

                                Toggle("Text Box", isOn: $state.settings.overlayBoxEnabled)
                                    .font(.body)
                                    .fixedSize(horizontal: true, vertical: false)

                                // Box color picker (implied; no label)
                                ColorPicker("", selection: $uiBoxColor, supportsOpacity: true)
                                    .labelsHidden()
                                    .disabled(!state.settings.overlayBoxEnabled)
                                    .opacity(state.settings.overlayBoxEnabled ? 1.0 : 0.20)
                            }
                            .fixedSize(horizontal: true, vertical: false)

                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // Divider between sections
                    GridRow {
                        Divider().gridCellColumns(5)
                    }

                    // MARK: Burn-in options (Frames / Timecode / Filename)
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {
                            burnInGroup(title: "Frames",
                                        isOn: $state.settings.burnInFrames,
                                        pos: $state.settings.burnInFramesPosition)

                            fixedGap(burnInGroupGap)

                            burnInGroup(title: "Timecode",
                                        isOn: $state.settings.burnInTimecode,
                                        pos: $state.settings.burnInTimecodePosition)

                            fixedGap(burnInGroupGap)

                            burnInGroup(title: "Filename",
                                        isOn: $state.settings.burnInFilename,
                                        pos: $state.settings.burnInFilenamePosition)

                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }
                }
                .padding(StyleConstants.panelInsets)
                .padding(.top, StyleConstants.panelInsets.top) // base + extra top padding rule
                .transition(.opacity)
                
                // Divider between sections
                GridRow {
                    Divider().gridCellColumns(5)
                }

                // MARK: Filename Suffix (Overlays)
                GridRow {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Text("Filename Suffix").font(.headline)
                            Text("Example: \(exampleOverlayOutputName)")
                                .font(.caption)
                                .foregroundColor(C.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        TextField(overlaySuffixPlaceholder, text: $state.settings.overlaySuffix)
                            .panelTextFieldStyle(C)
                            .help("Appends this to the output filename before the extension.")
                            .onChange(of: state.settings.overlaySuffix) { _ in
                                Task { @MainActor in
                                    AppCore.shared.applyNamingChangeToQueue(reason: AppCore.NamingChangeReason.suffixChanged)
                                }
                            }
                    }
                    .gridCellColumns(5)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration),
                   value: state.settings.overlaysExpanded)
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
        .onChange(of: state.settings.burnInFrames) { _ in
            applyOverlaySuffixAutosuggestionIfAppropriate()
            Task { @MainActor in
                AppCore.shared.applyNamingChangeToQueue(reason: AppCore.NamingChangeReason.suffixChanged)
            }
        }
        .onChange(of: state.settings.burnInTimecode) { _ in
            applyOverlaySuffixAutosuggestionIfAppropriate()
            Task { @MainActor in
                AppCore.shared.applyNamingChangeToQueue(reason: AppCore.NamingChangeReason.suffixChanged)
            }
        }
        .onChange(of: state.settings.burnInFilename) { _ in
            applyOverlaySuffixAutosuggestionIfAppropriate()
            Task { @MainActor in
                AppCore.shared.applyNamingChangeToQueue(reason: AppCore.NamingChangeReason.suffixChanged)
            }
        }

        .onAppear {
            // existing onAppear color setup stays
            // and also:
            applyOverlaySuffixAutosuggestionIfAppropriate()
        }
    }
    
    
    // MARK: Helpers
    
    private func burnInGroup(
        title: String,
        isOn: Binding<Bool>,
        pos: Binding<BurnInPosition>
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {

            Toggle("", isOn: isOn)
                .labelsHidden()

            Spacer().frame(width: checkToLabelGap)

            Text(title)
                .font(.body)
                .fixedSize(horizontal: true, vertical: false)

            // Keep the “label-to-grid” spacing consistent even when hidden:
            Spacer().frame(width: labelToGridGap)

            if isOn.wrappedValue {
                UI_PositionPicker(selection: pos)
                    .frame(width: positionPickerWidth, alignment: .leading)
            } else {
                // Preserve layout footprint so inter-group gaps stay identical
                Color.clear
                    .frame(width: positionPickerWidth, height: 1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func fixedGap(_ w: CGFloat) -> some View {
        Color.clear
            .frame(width: w, height: 1)
            .fixedSize()
    }
    
    
    // MARK: - Overlay naming / suffix

    private var isOverlayActive: Bool {
        state.settings.burnInFrames || state.settings.burnInTimecode || state.settings.burnInFilename
    }

    private var isTimecodeOnly: Bool {
        state.settings.burnInTimecode && !state.settings.burnInFrames && !state.settings.burnInFilename
    }

    /// Treat empty or “known suggested” values as eligible for auto-replace.
    private func overlaySuffixIsSuggestedOrEmpty(_ s: String) -> Bool {
        let cur = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if cur.isEmpty { return true }
        let tc = applySuggestedSeparator("TC", settings: state.settings)
        let bi = applySuggestedSeparator("BURNIN", settings: state.settings)
        return cur == tc || cur == bi
    }

    private func suggestedOverlaySuffix() -> String {
        if !isOverlayActive { return "" }
        return isTimecodeOnly
            ? applySuggestedSeparator("TC", settings: state.settings)
            : applySuggestedSeparator("BURNIN", settings: state.settings)
    }

    private func notifyNamingChanged() {
        Task { @MainActor in
            AppCore.shared.applyNamingChangeToQueue(reason: AppCore.NamingChangeReason.suffixChanged)
        }
    }

    /// Call this after any overlay toggle change that affects the suggestion.
    /// Only writes if the user hasn't customized the suffix.
    private func applyOverlaySuffixAutosuggestionIfAppropriate() {
        let cur = state.settings.overlaySuffix
        guard overlaySuffixIsSuggestedOrEmpty(cur) else { return }

        let next = suggestedOverlaySuffix()
        if cur != next {
            state.settings.overlaySuffix = next
            // Naming refresh will be triggered by the TextField onChange,
            // but call explicitly here too in case next == "" and the user never focuses the field.
            notifyNamingChanged()
        }
    }

    private var exampleOverlayOutputName: String {
        let base = state.files.first?.url.deletingPathExtension().lastPathComponent ?? "myfile"
        let ext  = state.settings.containerFormat.fileExtension

        let cur = state.settings.overlaySuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown: String

        if !isOverlayActive {
            shown = ""
        } else if !cur.isEmpty {
            shown = cur
        } else {
            shown = suggestedOverlaySuffix()   // TC-only => TC, else BURNIN (with separator)
        }

        return "\(base)\(shown).\(ext)"
    }

}
