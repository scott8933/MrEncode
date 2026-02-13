import SwiftUI

struct UI_NCLCOptions: View {
    @EnvironmentObject var state: AppState

    private enum C {
        static let pickerWidth: CGFloat = 260
        static let panelInsets = EdgeInsets(top: 6, leading: 12, bottom: 2, trailing: 6)
        static let sectionSpacing: CGFloat = 12
    }

    private static let nclcOptions: [String] = Settings.nclcOptionOrderTopFirst
    @State private var lastAutoLabel: String? = nil

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.nclcExpanded) {
                VStack(alignment: .leading, spacing: C.sectionSpacing) {

                    // Tags (renamed from "NCLC Tagging")
                    HStack(spacing: 12) {
                        Text("Tags").font(.headline)
                        Picker("", selection: $state.settings.nclcTag) {
                            ForEach(Self.nclcOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: C.pickerWidth, alignment: .leading)
                    }

                    // Color Label (appears first in filename)
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
                .padding(C.panelInsets)
                .padding(.top, C.panelInsets.top * 1.0)
            } label: {
                let inactive = state.settings.nclcTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no change"
                            && state.settings.nclcFilenameLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Text("NCLC Settings")
                    .font(.headline)
                    .opacity(inactive ? 0.35 : 1)
            }
        }
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

    // MARK: - Auto-suggest label

    private func applySuggestedLabel(for tag: String) {
        if isNoChange(tag) {
            if state.settings.nclcFilenameLabel == (lastAutoLabel ?? "") {
                state.settings.nclcFilenameLabel = ""
                lastAutoLabel = ""
            }
            return
        }
        let suggestion = suggestedLabel(for: tag)
        if state.settings.nclcFilenameLabel.isEmpty || state.settings.nclcFilenameLabel == (lastAutoLabel ?? "") {
            state.settings.nclcFilenameLabel = suggestion
            lastAutoLabel = suggestion
        }
    }

    private func isNoChange(_ tag: String) -> Bool {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "no change"
    }

    private func suggestedLabel(for tag: String) -> String {
        switch tag {
        case "1-1-1 (BT.709)":               return "BT709"
        case "1-13-1 (sRGB)":                return "sRGB"
        case "12-16-1 (P3-D65)":             return "P3D65"
        case "12-13-1 (DisplayP3)":          return "DisplayP3"
        case "9-16-9 (BT.2020)":             return "BT2020"
        case "9-18-9 (BT.2020 HLG)":         return "BT2020-HLG"
        case "9-16-10 (BT.2020 PQ CL)":      return "BT2020-PQ-CL"
        case "6-6-6 (Rec.601 NTSC)":         return "BT601-NTSC"
        case "5-6-5 (Rec.601 PAL)":          return "BT601-PAL"
        case "9-1-9 (BT.2020 SDR)":          return "BT2020-SDR"
        case "9-14-9 (BT.2020 SDR BT.1361)": return "BT2020-SDR-BT1361"
        case "1-4-1 (BT.709 γ2.2)":          return "BT709-G22"
        case "1-5-1 (BT.709 γ2.8)":          return "BT709-G28"
        default:
            if let start = tag.firstIndex(of: "("), let end = tag.lastIndex(of: ")"), start < end {
                return tag[tag.index(after: start)..<end]
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: "γ", with: "G")
            }
            return "NCLC"
        }
    }

    private var exampleOutputName: String {
        let base = state.files.first?.url.deletingPathExtension().lastPathComponent ?? "myfile"
        let ext  = state.files.first?.url.pathExtension.lowercased() ?? "mov"
        func norm(_ s: String) -> String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return "" }
            return t.hasPrefix("-") ? t : "-" + t
        }
        let color = norm(state.settings.nclcFilenameLabel)
        let comp  = norm(state.settings.outputSuffix)
        return "\(base)\(color)\(comp).\(ext)"
    }
}
