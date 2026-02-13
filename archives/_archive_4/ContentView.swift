//
//  ContentView.swift
//  MrHEVC
//
//  Main control panel for dropping QuickTime movies, choosing encode options,
//  and submitting jobs either locally (ffmpeg) or to Deadline.
//
//  Goals:
//  - Clean, modular sections
//  - Compact, left-hugging controls (no unexpected stretching)
//  - Bottom action bar is always visible (content scrolls under constraints)
//

import SwiftUI
import AppKit

struct ContentView: View {
    // App-wide state & settings
    @EnvironmentObject var state: AppState

    // Centralized UI constants
    fileprivate enum UI {
        static let pad: CGFloat = 16
        static let minWidth: CGFloat = 520
        static let minHeight: CGFloat = 900
        static let labelWidth: CGFloat = 90

        // Compact control widths
        static let pickerWidth: CGFloat = 240 // keeps NCLC menu from getting huge

        // Overlay position picker
        static let positionPickerWidth: CGFloat = 66 // ≈ 3*14 + gaps

        // GroupBox inner insets (more left & bottom breathing room)
        static let subpanelInsets = EdgeInsets(top: 6, leading: 14, bottom: 14, trailing: 6)

        // Fixed action bar height
        static let actionBarHeight: CGFloat = 52
    }

    // Integer formatter for Priority
    private static let intFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .none
        nf.minimum = 0
        nf.maximum = 100
        nf.allowsFloats = false
        return nf
    }()

    // NCLC options shown in the advanced panel (kept local & easy to extend)
    private static let nclcOptions: [String] = [
        "No Change",
        "1-1-1 (BT.709)",
        "1-13-1 (sRGB)",
        "9-16-9 (BT.2020)",
        "12-16-1 (P3-D65)",
        "12-13-1 (DisplayP3)",
        "6-6-6 (Rec.601 NTSC)",
        "5-6-5 (Rec.601 PAL)",
        "9-1-9 (BT.2020 SDR)",
        "9-14-9 (BT.2020 SDR BT.1361)",
        "12-1-1 (P3-D65 SDR)",
        "12-18-1 (P3-D65 HLG)",
        "9-18-9 (BT.2020 HLG)",
        "9-16-10 (BT.2020 PQ CL)",
        "1-4-1 (BT.709 γ2.2)",
        "1-5-1 (BT.709 γ2.8)"
    ]

    // Overlay appearance (UI colors mirrored to Settings via hex+alpha)
    @State private var uiTextColor: Color = .white
    @State private var uiBoxColor: Color  = Color.black.opacity(0.8)

    // Example output name preview for the suffix row
    private var exampleOutputName: String {
        let base = state.files.first?.url.deletingPathExtension().lastPathComponent ?? "myfile"
        let ext  = state.files.first?.url.pathExtension.lowercased() ?? "mov"
        return "\(base)\(state.settings.outputSuffix).\(ext)"
    }

    // MARK: - Body

    var body: some View {
        // Main content scrolls; bottom action bar is pinned
        ScrollView {
            VStack(spacing: 16) {

                // ── Title & Mode ───────────────────────────────────────────────
                SectionHeader("MrHEVC")
                header

                // ── Drop Zone ─────────────────────────────────────────────────
                SectionHeader("Drop QuickTime Movies")
                DropZoneView { state.addFiles($0) }
                    .frame(height: 140)
                    .padding(.bottom, 4)

                // ── Compact Options (Quality + Scale + Suffix) ───────────────
                compactOptions

                // ── Advanced Options (NCLC + Text Overlay + Burn-ins) ────────
                advancedOptions

                // ── Deadline Panel (only used if Remote mode) ────────────────
                deadlineOptions

                // ── Files Queued ─────────────────────────────────────────────
                SectionHeader("Files Queued")
                fileList
            }
            .padding(UI.pad)
            // Reserve space so content never hides behind the fixed action bar
            .padding(.bottom, UI.actionBarHeight + UI.pad)
        }
        .overlay(alignment: .bottom) {
            actionBar
                .frame(height: UI.actionBarHeight)
                .background(.bar)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        }
        .frame(minWidth: UI.minWidth, minHeight: UI.minHeight)

        // Persist settings when the view is closed
        .onDisappear { state.saveSettings() }

        // When the run mode changes: revalidate files + (optionally) refresh Deadline
        .onChange(of: state.settings.runMode) { newMode in
            state.revalidateFilesForCurrentMode()
            if newMode == .remoteDeadline && !state.deadlineAvailable {
                Task { await state.refreshDeadlineOptions(inBackground: true) }
            }
        }

        // Sync UI color pickers from Settings on appear
        .onAppear {
            uiTextColor = ColorFromHex(state.settings.overlayTextColorHex,
                                       alpha: state.settings.overlayTextColorAlpha)
            uiBoxColor  = ColorFromHex(state.settings.overlayBoxColorHex,
                                       alpha: state.settings.overlayBoxColorAlpha)
        }

        // Persist Text Color back to Settings
        .onChange(of: uiTextColor) { newValue in
            if let rgba = RGBA(newValue) {
                state.settings.overlayTextColorHex   = HexRGB(rgba.r, rgba.g, rgba.b)
                state.settings.overlayTextColorAlpha = rgba.a
            }
        }

        // Persist Box Color back to Settings
        .onChange(of: uiBoxColor) { newValue in
            if let rgba = RGBA(newValue) {
                state.settings.overlayBoxColorHex   = HexRGB(rgba.r, rgba.g, rgba.b)
                state.settings.overlayBoxColorAlpha = rgba.a
            }
        }
    }

    // MARK: - Sections

    /// Title row with mode picker
    private var header: some View {
        HStack(spacing: 12) {
            Text("MrHEVC").font(.largeTitle).bold()
            Spacer()
            Picker("Mode", selection: $state.settings.runMode) {
                ForEach(RunMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .help("Choose Local (ffmpeg) or Remote (Deadline) execution.")
        }
        .padding(.vertical, 4)
    }

    /// Quick options: file suffix, inverted CRF slider, and scale
    private var compactOptions: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {

                // Filename Suffix
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text("Filename Suffix").font(.headline)
                        Text("Example: \(exampleOutputName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    TextField("-HEVC", text: $state.settings.outputSuffix)
                        .textFieldStyle(.roundedBorder)
                        .help("Appends this to the output filename before the extension.")
                }

                // Row: Quality (CRF) + Scale
                HStack(spacing: 20) {

                    // Quality (CRF 14–30; lower is higher quality)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Quality").font(.headline)
                            Text("(CRF \(state.settings.qualityCRF))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // Inverted slider: left = smaller file (higher CRF), right = best quality (lower CRF)
                        HStack {
                            Text("Smaller file")
                                .font(.caption)
                                .foregroundColor(.primary) // readable
                            let crfMin = 14.0, crfMax = 30.0, crfSum = crfMin + crfMax // 44
                            Slider(
                                value: Binding(
                                    get: { crfSum - Double(state.settings.qualityCRF) },
                                    set: { state.settings.qualityCRF = Int((crfSum - $0).rounded()) }
                                ),
                                in: crfMin...crfMax, step: 1
                            )
                            Text("Best quality")
                                .font(.caption)
                                .foregroundColor(.primary) // readable
                        }
                        .help("Left = smaller file (higher CRF). Right = best quality (lower CRF).")
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 48)

                    // Scale
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scale").font(.headline)
                        Picker("Scale", selection: $state.settings.scale) {
                            ForEach(ScaleOption.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .help("Downscale before encoding to reduce output resolution/bitrate.")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(UI.subpanelInsets)
        }
    }

    /// Advanced: color tagging + text overlay (appearance) + burn-ins
    private var advancedOptions: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.advancedExpanded) {
                VStack(alignment: .leading, spacing: 12) {

                    // NCLC Tagging — compact, non-expanding
                    LabeledField("NCLC Tagging", fills: false) {
                        Picker("", selection: $state.settings.nclcTag) {
                            ForEach(Self.nclcOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: UI.pickerWidth, alignment: .leading)
                    }

                    Divider()

                    // Text Overlay — single compact, left-hugging line (matches "NCLC Tagging" sizing)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Text Overlay").font(.headline)

                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Text Color") // default body, matches NCLC label style
                            ColorPicker("", selection: $uiTextColor, supportsOpacity: true)
                                .labelsHidden()

                            Toggle("Text Box", isOn: $state.settings.overlayBoxEnabled)
                                .font(.body) // match "NCLC Tagging" label sizing

                            Text("Box Color")
                                .font(.body)
                                .opacity(state.settings.overlayBoxEnabled ? 1.0 : 0.5)

                            ColorPicker("", selection: $uiBoxColor, supportsOpacity: true)
                                .labelsHidden()
                                .disabled(!state.settings.overlayBoxEnabled)
                                .opacity(state.settings.overlayBoxEnabled ? 1.0 : 0.35)
                        }
                        .fixedSize(horizontal: true, vertical: false) // hug content, no stretch
                    }

                    Divider()

                    // Burn-ins — one compact horizontal line (Frames, Timecode, Filename)
                    HStack(alignment: .center, spacing: 24) {
                        OverlayTogglePosition(
                            title: "Frames",
                            isOn: $state.settings.burnInFrames,
                            position: $state.settings.burnInFramesPosition
                        )

                        OverlayTogglePosition(
                            title: "Timecode",
                            isOn: $state.settings.burnInTimecode,
                            position: $state.settings.burnInTimecodePosition
                        )

                        OverlayTogglePosition(
                            title: "Filename",
                            isOn: $state.settings.burnInFilename,
                            position: $state.settings.burnInFilenamePosition
                        )

                        Spacer(minLength: 0) // keep the row left-hugging
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(UI.subpanelInsets)
            } label: {
                Text("Advanced Options").font(.headline)
            }
        }
    }

    /// Deadline job options (visible/usable in Remote mode; disabled otherwise)
    private var deadlineOptions: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.deadlineExpanded) {

                // Availability / error info
                if let err = state.deadlineError, !state.deadlineAvailable {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .textSelection(.enabled)
                } else if !state.deadlineAvailable {
                    Text("Couldn’t reach Deadline. Cached lists will be used if available; otherwise jobs will run locally.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                let jobOptionsDisabled =
                    (state.settings.runMode != .remoteDeadline) ||
                    (!state.deadlineAvailable && state.settings.poolOptions.isEmpty)

                VStack(alignment: .leading, spacing: 10) {

                    LabeledField("Priority") {
                        TextField("0–100",
                                  value: $state.settings.priority,
                                  formatter: Self.intFormatter
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    // Pool / Secondary / Group row
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Pool").frame(width: UI.labelWidth, alignment: .trailing)

                        HStack(spacing: 8) {
                            Picker("", selection: $state.settings.pool) {
                                ForEach(state.settings.poolOptions, id: \.self) {
                                    Text($0.isEmpty ? "—" : $0).tag($0)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize(horizontal: true, vertical: false)

                            CompactPicker(title: "Secondary",
                                          selection: $state.settings.secondaryPool,
                                          options: state.settings.poolOptions)

                            CompactPicker(title: "Group",
                                          selection: $state.settings.group,
                                          options: state.settings.groupOptions)
                        }
                    }

                    LabeledField("Batch Name") {
                        TextField("optional", text: $state.settings.batchName)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledField("Job Name") {
                        TextField("optional", text: $state.settings.jobName)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledField("Comment") {
                        TextField("optional", text: $state.settings.comment)
                            .textFieldStyle(.roundedBorder)
                    }

                    LabeledField("Dependencies") {
                        TextField("JobIDs comma-separated", text: $state.settings.dependencies)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .disabled(jobOptionsDisabled)
                .animation(.default, value: jobOptionsDisabled)
                .padding(UI.subpanelInsets)

            } label: {
                HStack(spacing: 10) {
                    Text("Deadline Options").font(.headline)
                    Spacer()
                    if state.isRefreshingDeadline { ProgressView().scaleEffect(0.8) }
                    Text(statusText)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(statusColor.opacity(0.15))
                        .clipShape(Capsule())
                        .accessibilityLabel("Deadline status: \(statusText)")
                }
            }
        }
    }

    /// Files queued list
    private var fileList: some View {
        GroupBox {
            List(state.files) { item in
                let outputName = OutputNamer
                    .suggestedOutputURL(for: item.url, settings: state.settings)
                    .lastPathComponent

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outputName)
                            .lineLimit(1)
                            .help(item.url.path)

                        if item.status == .blocked, let reason = item.statusReason {
                            Text(reason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    // Right-side status indicator
                    switch item.status {
                    case .queued:
                        Image(systemName: "circle.dotted").foregroundColor(.gray)
                    case .encoding:
                        ProgressView().scaleEffect(0.7)
                    case .done:
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    case .error:
                        Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
                    case .blocked:
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.gray)
                    }
                }
                .opacity(item.status == .blocked ? 0.5 : 1.0) // gray out blocked rows
            }
            // Give the list a touch more left/bottom space (top/right already feel good)
            .padding(.leading, UI.subpanelInsets.leading)
            .padding(.bottom,  UI.subpanelInsets.bottom)
            .frame(minHeight: 80)
        }
    }

    /// Bottom action bar (Clear / Encode/Submit) — always visible
    private var actionBar: some View {
        HStack {
            Button("Clear") { state.clear() }
                .disabled(state.files.isEmpty)

            Spacer()

            Button(state.settings.runMode == .remoteDeadline ? "Submit to Deadline" : "Encode Locally") {
                state.submit()
            }
            .disabled(state.files.isEmpty)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, UI.pad)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }

    // MARK: - Status helpers

    private var statusText: String {
        if state.deadlineAvailable {
            if let ts = state.settings.lastDeadlineFetch {
                return Date().timeIntervalSince(ts) < 3600 ? "Connected" : "Cached"
            }
            return "Cached"
        } else {
            return state.settings.poolOptions.isEmpty && state.settings.groupOptions.isEmpty
                ? "Unavailable"
                : "Cached"
        }
    }

    private var statusColor: Color {
        state.deadlineAvailable ? .green : .orange
    }
}

// MARK: - Visual Section Header

/// Lightweight section header with an underline divider.
private struct SectionHeader: View {
    var title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        HStack { Text(title).font(.title3).bold(); Spacer() }
            .padding(.top, 2)
            .overlay(Divider().offset(y: 16), alignment: .bottom)
            .padding(.bottom, 8)
    }
}

// MARK: - Small UI utilities

private struct CompactPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { Text($0.isEmpty ? "—" : $0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

/// Form row with right-aligned fixed label column.
/// `fills` controls whether the content expands horizontally.
private struct LabeledField<Content: View>: View {
    let label: String
    let fills: Bool
    let content: () -> Content

    init(_ label: String,
         fills: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.fills = fills
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .frame(width: ContentView.UI.labelWidth, alignment: .trailing)
            if fills {
                content().frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content()
            }
        }
    }
}

/// A single inline control: [Toggle(title)] [PositionPicker]
private struct OverlayTogglePosition: View {
    let title: String
    @Binding var isOn: Bool
    @Binding var position: BurnInPosition

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(title, isOn: $isOn)
            PositionPicker(selection: $position)
                .frame(width: ContentView.UI.positionPickerWidth, alignment: .leading)
                .disabled(!isOn)
                .opacity(isOn ? 1.0 : 0.35)
        }
        .fixedSize(horizontal: true, vertical: false) // hug natural size
    }
}

/// Compact 3×3 position selector (corners + edge centers). Center is disabled.
private struct PositionPicker: View {
    @Binding var selection: BurnInPosition

    private let grid: [[BurnInPosition?]] = [
        [.upperLeft,  .upperCenter,  .upperRight],
        [.middleLeft, nil,           .middleRight],
        [.lowerLeft,  .lowerCenter,  .lowerRight]
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(grid.indices, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(grid[r].indices, id: \.self) { c in
                        PositionCell(position: grid[r][c], selection: $selection)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Burn-in position")
    }
}

private struct PositionCell: View {
    let position: BurnInPosition?          // nil = center (disabled)
    @Binding var selection: BurnInPosition // live binding

    var body: some View {
        Group {
            if let pos = position {
                let isSelected = (selection == pos)
                Button {
                    selection = pos
                } label: {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.45),
                                lineWidth: isSelected ? 2 : 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tooltip(for: pos))
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.clear)
                    .frame(width: 14, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
                    .opacity(0.4)
                    .accessibilityHidden(true)
            }
        }
    }

    private func tooltip(for p: BurnInPosition) -> String {
        switch p {
        case .upperLeft:   return "Upper Left"
        case .upperCenter: return "Top Center"
        case .upperRight:  return "Upper Right"
        case .middleLeft:  return "Middle Left"
        case .middleRight: return "Middle Right"
        case .lowerLeft:   return "Lower Left"
        case .lowerCenter: return "Bottom Center"
        case .lowerRight:  return "Lower Right"
        }
    }
}

// MARK: - Color helpers (SwiftUI <-> Settings hex + alpha)

/// Build a SwiftUI Color from #RRGGBB + alpha.
private func ColorFromHex(_ hex: String, alpha: Double) -> Color {
    let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "#", with: "")
    guard clean.count == 6,
          let r = Int(clean.prefix(2), radix: 16),
          let g = Int(clean.dropFirst(2).prefix(2), radix: 16),
          let b = Int(clean.suffix(2), radix: 16)
    else { return Color(.sRGB, red: 1, green: 1, blue: 1, opacity: alpha) }
    return Color(.sRGB, red: Double(r)/255.0,
                         green: Double(g)/255.0,
                         blue: Double(b)/255.0,
                         opacity: alpha)
}

/// Convert SwiftUI Color → sRGB RGBA components (0...1). Returns nil if conversion fails.
private func RGBA(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double)? {
    guard let cg = color.cgColor,
          let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB)
    else { return nil }
    return (Double(ns.redComponent),
            Double(ns.greenComponent),
            Double(ns.blueComponent),
            Double(ns.alphaComponent))
}

/// Encode #RRGGBB string from sRGB components (0...1).
private func HexRGB(_ r: Double, _ g: Double, _ b: Double) -> String {
    let R = max(0, min(255, Int(round(r * 255))))
    let G = max(0, min(255, Int(round(g * 255))))
    let B = max(0, min(255, Int(round(b * 255))))
    return String(format: "#%02X%02X%02X", R, G, B)
}
