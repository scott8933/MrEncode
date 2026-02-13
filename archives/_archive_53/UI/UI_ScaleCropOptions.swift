//
//  UI_ScaleCropOptions.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/16/25.
//

import SwiftUI

struct UI_ScaleCropOptions: View {
    @EnvironmentObject var state: AppState

    private let itemGap: CGFloat = 2
    private var groupGap: CGFloat = 30
    private let modePickerWidth: CGFloat = 220

    var body: some View {
        let inactive =
            (state.settings.scale == .oneToOne)
            && state.settings.scaleSuffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        VStack(alignment: .leading, spacing: 0) {

            // Header (match CompressionOptions)
            Button {
                withAnimation(.easeInOut(duration: StyleConstants.expandAnimationDuration)) {
                    state.settings.scaleExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: state.settings.scaleExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                    
                    let dimHeader = !state.settings.overlaysExpanded && inactive

                    Text("Scale & Crop")
                        .font(.headline)
                        .opacity(inactive ? 0.35 : 1.0)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if state.settings.scaleExpanded {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: StyleConstants.sectionSpacing) {

                    // MARK: Scale | Mode  (match Compression "Item | Dropdown" row)
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {

                            // Left group: Scale
                            HStack(spacing: itemGap) {
                                Text("Scale")
                                    .font(.headline)
                                    .fixedSize(horizontal: true, vertical: false)

                                Picker("", selection: $state.settings.scale) {
                                    Text("No Scale (1:1)").tag(ScaleOption.oneToOne)
                                    Text("Half (1/2)").tag(ScaleOption.half)
                                    Text("Quarter (1/4)").tag(ScaleOption.quarter)
                                    Text("Custom").tag(ScaleOption.custom)
                                }
                                .pickerStyle(.menu)
                                .help("Resize before encoding.")
                                .onChange(of: state.settings.scale) { newScale in
                                    applyScaleSelectionToSuffix(newScale)
                                }
                            }

                            Color.clear
                                .frame(width: groupGap)

                            // Right group: Mode
                            HStack(spacing: itemGap) {
                                Text("Mode")
                                    .font(.headline)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .opacity(isCustom ? 1.0 : 0.35)

                                Picker("", selection: $state.settings.customScaleMode) {
                                    Text("Stretch (force exact)").tag(CustomScaleMode.stretch)
                                    Text("Fit (letterbox/pillarbox)").tag(CustomScaleMode.fit)
                                    Text("Fill (crop)").tag(CustomScaleMode.fill)
                                }
                                .pickerStyle(.menu)
                                .disabled(!isCustom)
                                .opacity(isCustom ? 1.0 : 0.35)
                            }
                            .help("Stretch forces exact size. Fit preserves aspect and adds letterbox/pillarbox. Fill preserves aspect and crops.")

                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // MARK: Size + Anchor (Custom only)
                    if isCustom {

                        // Size row
                        GridRow {
                            HStack(spacing: itemGap) {
                                Text("Size")
                                    .font(.headline)
                                    .fixedSize(horizontal: true, vertical: false)

                                TextField("", value: intBinding(get: {
                                    state.settings.customScaleWidth
                                }, set: { v in
                                    state.settings.customScaleWidth = v
                                    applySuggestedSuffixIfAppropriate(scale: state.settings.scale)
                                }), formatter: numberFormatter)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 76, alignment: .leading)

                                Text("×")
                                    .font(.headline)

                                TextField("", value: intBinding(get: {
                                    state.settings.customScaleHeight
                                }, set: { v in
                                    state.settings.customScaleHeight = v
                                    applySuggestedSuffixIfAppropriate(scale: state.settings.scale)
                                }), formatter: numberFormatter)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 76, alignment: .leading)

                                Spacer(minLength: 0)
                            }
                            .gridCellColumns(5)
                        }

                        // Anchor picker
                        GridRow {
                            HStack(spacing: itemGap) {
                                Text("Anchor")
                                    .font(.headline)
                                    .frame(width: 60, alignment: .leading)

                                UI_PositionPicker(selection: $state.settings.customScaleAnchor)
                                    .help("Controls where padding/cropping is applied for Fit/Fill.")
                            }
                            .gridCellColumns(5)
                        }
                    }

                    // MARK: Filename Suffix (match Compression verbiage/layout)
                    GridRow {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                Text("Filename Suffix").font(.headline)
                                Text("Example: \(exampleSuffixText)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            TextField("", text: $state.settings.scaleSuffix)
                                .textFieldStyle(.roundedBorder)
                                .help("Appends this to the output filename before the extension.")
                        }
                        .gridCellColumns(5)
                    }
                }
                .padding(StyleConstants.panelInsets)
                .padding(.top, StyleConstants.panelInsets.top)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration),
                   value: state.settings.scaleExpanded)
        .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration),
                   value: state.settings.scale)
    }


    // MARK: - Derived

    private var isCustom: Bool { state.settings.scale == .custom }

    private var exampleSuffixText: String {
        if isCustom {
            let w = evenize(state.settings.customScaleWidth)
            let h = evenize(state.settings.customScaleHeight)
            return applySuggestedSeparator("\(w)x\(h)", settings: state.settings)
        }
        return "\(applySuggestedSeparator("HALF", settings: state.settings)), \(applySuggestedSeparator("QUARTER", settings: state.settings))"
    }

    // MARK: - Suffix suggestion logic

    private func applySuggestedSuffixIfAppropriate(scale: ScaleOption) {
        let cur = state.settings.scaleSuffix.trimmingCharacters(in: .whitespacesAndNewlines)

        // Treat these as “suggested” values we’re allowed to overwrite automatically.
        let suggestedHalf    = applySuggestedSeparator("HALF", settings: state.settings)
        let suggestedQuarter = applySuggestedSeparator("QUARTER", settings: state.settings)

        let wasSuggestedPreset =
            cur.isEmpty ||
            cur == suggestedHalf ||
            cur == suggestedQuarter

        let wasSuggestedCustom: Bool = {
            guard !cur.isEmpty else { return false }

            let sep = state.settings.suffixSeparator.trimmingCharacters(in: .whitespacesAndNewlines)
            // If sep is empty, we have no prefix convention—treat custom as "not suggested".
            guard !sep.isEmpty else { return false }

            // Strip exactly one leading sep (supports multi-char seps)
            let stripped = cur.hasPrefix(sep) ? String(cur.dropFirst(sep.count)) : cur

            return stripped.range(of: #"^\d+x\d+$"#, options: .regularExpression) != nil
        }()

        switch scale {
        case .oneToOne:
            if wasSuggestedPreset || wasSuggestedCustom {
                state.settings.scaleSuffix = ""
            }
        case .half:
            if wasSuggestedPreset || wasSuggestedCustom {
                state.settings.scaleSuffix = applySuggestedSeparator("HALF", settings: state.settings)
            }
        case .quarter:
            if wasSuggestedPreset || wasSuggestedCustom {
                state.settings.scaleSuffix = applySuggestedSeparator("QUARTER", settings: state.settings)
            }
        case .custom:
            if cur.isEmpty {
                let w = evenize(state.settings.customScaleWidth)
                let h = evenize(state.settings.customScaleHeight)
                state.settings.scaleSuffix = applySuggestedSeparator("\(w)x\(h)", settings: state.settings)
            }
        }
    }

    // MARK: - Helpers
    
    private var numberFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 2
        return f
    }

    private func intBinding(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Int> {
        Binding(
            get: { get() },
            set: { newVal in set(max(2, newVal)) }
        )
    }

    private func evenize(_ n: Int) -> Int { (n % 2 == 0) ? n : (n + 1) }
    
    private func applyScaleSelectionToSuffix(_ scale: ScaleOption) {
        switch scale {
        case .oneToOne:
            // Pass-through: clear
            state.settings.scaleSuffix = ""

        case .half:
            state.settings.scaleSuffix = applySuggestedSeparator("HALF", settings: state.settings)

        case .quarter:
            state.settings.scaleSuffix = applySuggestedSeparator("QUARTER", settings: state.settings)

        case .custom:
            // On dropdown change, always reset to current custom resolution
            let w = evenize(state.settings.customScaleWidth)
            let h = evenize(state.settings.customScaleHeight)
            state.settings.scaleSuffix = applySuggestedSeparator("\(w)x\(h)", settings: state.settings)
        }
    }

}

