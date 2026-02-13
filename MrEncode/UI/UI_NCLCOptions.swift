//
//  UI_NCLCOptions.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/16/25.
//

import SwiftUI

struct UI_NCLCOptions: View {
    @EnvironmentObject var state: AppState
    
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    private static let nclcOptions: [String] = Settings.nclcOptionOrderTopFirst
    @State private var lastAutoLabel: String? = nil

    // Match Compression / Scale&Crop layout numbers (hardcoded for now)
    private let itemGap: CGFloat = 2
    private var groupGap: CGFloat = 30
    private let pickerWidth: CGFloat = 260

    var body: some View {
        let isExpanded = state.settings.nclcExpanded
        let isModified = state.isPanelModified(.nclc)

        VStack(alignment: .leading, spacing: 0) {

            Button {
                withAnimation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration)) {
                    state.settings.nclcExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(C.textSecondary)
                        .frame(width: 14, height: 14)

                    Text("NCLC Settings")
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
            if state.settings.nclcExpanded {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: StyleConstants.Spacing.sectionSpacing) {

                    // MARK: Tags
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {

                            HStack(spacing: itemGap) {
                                Text("Tags")
                                    .font(.headline)
                                    .fixedSize(horizontal: true, vertical: false)

                                Picker("", selection: $state.settings.nclcTag) {
                                    ForEach(Self.nclcOptions, id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(.menu)
                                .frame(width: pickerWidth, alignment: .leading)
                            }

                            Color.clear.frame(width: groupGap)
                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // MARK: Color Label
                    GridRow {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                Text("Color Label").font(.headline)
                                Text("Example: \(exampleOutputName)")
                                    .font(.caption)
                                    .foregroundColor(C.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            TextField("e.g. BT709", text: $state.settings.nclcFilenameLabel)
                                .panelTextFieldStyle(C)
                                .help("Optional color/gamut label added before your Compression suffix, e.g. “BT709”.")
                        }
                        .gridCellColumns(5)
                    }
                }
                .padding(StyleConstants.panelInsets)
                .padding(.top, StyleConstants.panelInsets.top) // base + extra top padding rule
                .transition(.opacity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: StyleConstants.Motion.expandAnimationDuration),
                   value: state.settings.nclcExpanded)
        .onAppear {
            if isNoChange(state.settings.nclcTag),
               state.settings.nclcFilenameLabel == (lastAutoLabel ?? "") {
                state.settings.nclcFilenameLabel = ""
                lastAutoLabel = ""
            }
        }
        .onChange(of: state.settings.nclcTag) { newTag in
            applySuggestedLabel(for: newTag)
        }
    }


    // MARK: - Helpers

    private func applySuggestedLabel(for tag: String) {
        if isNoChange(tag) {
            state.settings.nclcFilenameLabel = ""
            lastAutoLabel = ""
            return
        }

        let suggestion = applySuggestedSeparator(
            suggestedLabel(for: tag),
            settings: state.settings
        )

        let current = state.settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        if current.isEmpty || current == (lastAutoLabel ?? "") {
            state.settings.nclcFilenameLabel = suggestion
            lastAutoLabel = suggestion
        } else {
            lastAutoLabel = suggestion
        }
    }

    private func isNoChange(_ tag: String) -> Bool {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        return t == "no change" || t == "no-change" || t == "none" || t == "unchanged"
    }

    private func suggestedLabel(for tag: String) -> String {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if t.contains("2020") || t.contains("bt.2020") || t.contains("bt2020") || t.contains("hdr10") {
            return "BT2020"
        }
        if t.contains("p3") || t.contains("display p3") || t.contains("display-p3")
            || t.contains("p3-d65") || t.contains("p3 d65") {
            return "P3"
        }
        if t.contains("709") || t.contains("bt.709") || t.contains("bt709")
            || t.contains("rec.709") || t.contains("rec709") {
            return "BT709"
        }
        if t.contains("srgb") {
            return "sRGB"
        }
        if t.contains("601") || t.contains("bt601") || t.contains("rec601") {
            return "BT601"
        }

        return ""
    }

    private var exampleOutputName: String {
        let base = state.files.first?.url
            .deletingPathExtension()
            .lastPathComponent ?? "myfile"

        let ext = state.settings.containerFormat.fileExtension

        let label = state.settings.nclcFilenameLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let suffix: String = {
            let s = state.settings.outputSuffix
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
            if state.settings.containerFormat == .mp4 { return "" }
            return applySuggestedSeparator("HEVC", settings: state.settings)
        }()

        let labelPart = label.isEmpty ? "" : label
        return "\(base)\(labelPart)\(suffix).\(ext)"
    }
}
