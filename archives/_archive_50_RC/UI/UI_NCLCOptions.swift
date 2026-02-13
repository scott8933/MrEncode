//
//  UI_NCLCOptions.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/16/25.
//

import SwiftUI

struct UI_NCLCOptions: View {
    @EnvironmentObject var state: AppState

    private static let nclcOptions: [String] = Settings.nclcOptionOrderTopFirst
    @State private var lastAutoLabel: String? = nil

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.nclcExpanded) {
                VStack(alignment: .leading, spacing: StyleConstants.sectionSpacing) {
                    HStack(spacing: 12) {
                        Text("Tags").font(.headline)
                        Picker("", selection: $state.settings.nclcTag) {
                            ForEach(Self.nclcOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: StyleConstants.nclcPickerWidth, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Text("Color Label").font(.headline)
                            Text("Example: \(exampleOutputName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        TextField("e.g. BT709", text: $state.settings.nclcFilenameLabel)
                            .textFieldStyle(.roundedBorder)
                            .help("Optional color/gamut label added before your Compression suffix, e.g. “BT709”.")
                    }
                }
                .padding(StyleConstants.panelInsets)
                .padding(.top, StyleConstants.panelInsets.top)
            } label: {
                let inactive = state.settings.nclcTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no change"
                            && state.settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Text("NCLC Settings")
                    .font(.headline)
                    .opacity(inactive ? 0.35 : 1)
            }
        }
        .onAppear {
            // If user left it on "No Change" and label equals what we auto-set previously, clear it.
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

    /// When the tag changes, suggest a label (non-destructive to custom labels).
    private func applySuggestedLabel(for tag: String) {
        if isNoChange(tag) {
            // Clear label for No Change
            state.settings.nclcFilenameLabel = ""
            lastAutoLabel = ""
            return
        }

        let suggestion = suggestedLabel(for: tag)
        let current = state.settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only apply if empty or was previously our auto suggestion
        if current.isEmpty || current == (lastAutoLabel ?? "") {
            state.settings.nclcFilenameLabel = suggestion
            lastAutoLabel = suggestion
        } else {
            // Respect user's custom label; update our memory so we don't overwrite next time.
            lastAutoLabel = suggestion
        }
    }

    /// Match common "no change" labels robustly.
    private func isNoChange(_ tag: String) -> Bool {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        return t == "no change" || t == "no-change" || t == "none" || t == "unchanged"
    }

    /// Suggest a short filename label from a variety of tag wordings.
    private func suggestedLabel(for tag: String) -> String {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Substring checks to be resilient to different option captions
        if t.contains("2020") || t.contains("bt.2020") || t.contains("bt2020") || t.contains("hdr10") {
            return "BT2020"
        }
        if t.contains("p3") || t.contains("display p3") || t.contains("display-p3") || t.contains("p3-d65") || t.contains("p3 d65") {
            return "P3"
        }
        if t.contains("709") || t.contains("bt.709") || t.contains("bt709") || t.contains("rec.709") || t.contains("rec709") {
            return "BT709"
        }
        if t.contains("srgb") {
            return "sRGB"
        }
        if t.contains("601") || t.contains("bt601") || t.contains("rec601") {
            return "BT601"
        }

        // Fallback: empty label when we can't infer
        return ""
    }

    /// Example of how the label will appear in the filename.
    private var exampleOutputName: String {
        let base = state.files.first?.url.deletingPathExtension().lastPathComponent ?? "myfile"
        let ext = state.settings.containerFormat.fileExtension
        let label = state.settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        // Compression suffix logic mirrors CompressionOptions
        let suffix: String = {
            let s = state.settings.outputSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
            return state.settings.containerFormat == .mp4 ? "" : "-HEVC"
        }()

        let labelPart = label.isEmpty ? "" : "-\(label)"
        return "\(base)\(labelPart)\(suffix).\(ext)"
    }
}
