import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState
    
    private let nclcOptions: [String] = [
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


    var body: some View {
        VStack(spacing: 16) {

            // ─── App Title & Mode ───────────────────────────────────────────────
            SectionHeader("MrHEVC")
            header

            // ─── Drop Zone ─────────────────────────────────────────────────────
            SectionHeader("Drop QuickTime Movies")
            DropZoneView { state.addFiles($0) }
                .frame(height: 140)
                .padding(.bottom, 4)

            // ─── Compact Options (Quality + Scale) ─────────────────────────────
            compactOptions
            
            // ─── Advanced Options ───────────────────────────
            advancedOptions

            // ─── Deadline Panel ────────────────────────────────────────────────
            deadlineBox

            // ─── Files Queued ─────────────────────────────────────────────────
            SectionHeader("Files Queued")
            fileList
        }
        .padding(16)
        // Pin the action bar to the bottom so it never gets cropped
        .safeAreaInset(edge: .bottom) {
            actionBar
                .padding(.horizontal, 16)
                .background(.bar)
        }

        .frame(minWidth: 520, minHeight: 900)
        .onDisappear { state.saveSettings() }
        .onChange(of: state.settings.runMode) { newMode in
            if newMode == .remoteDeadline && !state.deadlineAvailable {
                Task { await state.refreshDeadlineOptions(inBackground: true) }
            }
        }
        .onChange(of: state.settings.runMode) { newMode in
            state.revalidateFilesForCurrentMode()
            if newMode == .remoteDeadline && !state.deadlineAvailable {
                Task { await state.refreshDeadlineOptions(inBackground: true) }
            }
        }

        

    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Text("MrHEVC")
                .font(.largeTitle).bold()
            Spacer()
            Picker("Mode", selection: $state.settings.runMode) {
                ForEach(RunMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
        }
        .padding(.vertical, 4)
    }

    // Compact: Quality (CRF) on left, Scale on right (50/50) + Filename Suffix
    private var compactOptions: some View {
        GroupBox {
            // Filename Suffix
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text("Filename Suffix")
                        .font(.headline)

                    Text(
                        "Example: \((state.files.first?.url.deletingPathExtension().lastPathComponent ?? "myfile"))\(state.settings.outputSuffix).\(state.files.first?.url.pathExtension.lowercased() ?? "mov")"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                }

                TextField("-HEVC", text: $state.settings.outputSuffix)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity) // span full panel width
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                // Row 1: Quality + Scale
                HStack(spacing: 20) {
                    // Left: Quality
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Quality").font(.headline)
                            Text("(CRF \(state.settings.qualityCRF))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Low")
                            Slider(
                                value: Binding(
                                    get: { Double(30 - (state.settings.qualityCRF - 14)) },
                                    set: { v in state.settings.qualityCRF = 30 - Int(v.rounded() - 14) }
                                ),
                                in: 14...30, step: 1
                            )
                            Text("Best!")
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 48)

                    // Right: Scale (vertical stack)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scale").font(.headline)
                        Picker("Scale", selection: $state.settings.scale) {
                            ForEach(ScaleOption.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(6)
        }
    }


    private var advancedOptions: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.advancedExpanded) {
                VStack(alignment: .leading, spacing: 12) {

                    // NCLC Tagging (moved here)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NCLC Tagging").font(.headline)
                        Picker("NCLC Tagging", selection: $state.settings.nclcTag) {
                            ForEach(nclcOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Divider()

                    // Burn-in options
                    VStack(alignment: .leading, spacing: 10) {

                        // Frames
                        HStack(alignment: .center, spacing: 12) {
                            Toggle("Overlay Frames", isOn: $state.settings.burnInFrames)
                            if state.settings.burnInFrames {
                                PositionPicker(selection: $state.settings.burnInFramesPosition)
                            }
                            Spacer(minLength: 0)
                        }

                        // Timecode
                        HStack(alignment: .center, spacing: 12) {
                            Toggle("Overlay Timecode", isOn: $state.settings.burnInTimecode)
                            if state.settings.burnInTimecode {
                                PositionPicker(selection: $state.settings.burnInTimecodePosition)
                            }
                            Spacer(minLength: 0)
                        }

                        // Filename
                        HStack(alignment: .center, spacing: 12) {
                            Toggle("Overlay Filename", isOn: $state.settings.burnInFilename)
                            if state.settings.burnInFilename {
                                PositionPicker(selection: $state.settings.burnInFilenamePosition)
                            }
                            Spacer(minLength: 0)
                        }
                    }

                }
                .padding(.top, 8)
            } label: {
                Text("Advanced Options")
                    .font(.headline)
            }
        }
    }

    

    // Compact layout with per-field label widths and precise spacing
    private var deadlineBox: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.deadlineExpanded) {
                // ── Content (unchanged) ───────────────────────────────────────────
                // Error / info
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

                // Disable job options when not Remote or no lists yet
                let jobOptionsDisabled =
                    (state.settings.runMode != .remoteDeadline) ||
                    (!state.deadlineAvailable && state.settings.poolOptions.isEmpty)

                VStack(alignment: .leading, spacing: 8) {

                    // Priority
                    LabeledField("Priority",
                        content: TextField("0–100",
                            value: $state.settings.priority,
                            formatter: NumberFormatter()
                        )
                        .textFieldStyle(.roundedBorder)
                    )

                    // Pool / Secondary / Group row (aligned with other fields)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Pool")
                            .frame(width: 90, alignment: .trailing)   // main row label, aligned like others

                        HStack(spacing: 8) {
                            // First dropdown: shrink-to-fit (no inline label)
                            Picker("", selection: $state.settings.pool) {
                                ForEach(state.settings.poolOptions, id: \.self) {
                                    Text($0.isEmpty ? "—" : $0).tag($0)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize(horizontal: true, vertical: false)  // ← shrink to fit content

                            // Secondary with inline label
                            CompactPicker(title: "Secondary",
                                          selection: $state.settings.secondaryPool,
                                          options: state.settings.poolOptions)

                            // Group with inline label
                            CompactPicker(title: "Group",
                                          selection: $state.settings.group,
                                          options: state.settings.groupOptions)
                        }
                    }

                    // Batch Name (optional)
                    LabeledField("Batch Name",
                        content: TextField("optional", text: $state.settings.batchName)
                            .textFieldStyle(.roundedBorder)
                    )

                    // Job name & comment
                    LabeledField("Job Name",
                        content: TextField("optional", text: $state.settings.jobName)
                            .textFieldStyle(.roundedBorder)
                    )
                    LabeledField("Comment",
                        content: TextField("optional", text: $state.settings.comment)
                            .textFieldStyle(.roundedBorder)
                    )

                    // Dependencies
                    LabeledField("Dependencies",
                        content: TextField("JobIDs comma-separated", text: $state.settings.dependencies)
                            .textFieldStyle(.roundedBorder)
                    )
                }
                .disabled(jobOptionsDisabled)
                .animation(.default, value: jobOptionsDisabled)
                .padding(.top, 4)
                // ──────────────────────────────────────────────────────────────────

            } label: {
                // ── Header (visually identical to your current mini-header row) ───
                HStack(spacing: 10) {
                    Text("Deadline Options").font(.headline)
                    Spacer()
                    if state.isRefreshingDeadline {
                        ProgressView().scaleEffect(0.8)
                    }
                    Text(statusText)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(statusColor.opacity(0.15))
                        .clipShape(Capsule())
                }
                // ──────────────────────────────────────────────────────────────────
            }
        }
        .padding(6)
    }


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
                        Image(systemName: "circle.dotted")
                            .foregroundColor(.gray)

                    case .encoding:
                        ProgressView()
                            .scaleEffect(0.7)

                    case .done:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)

                    case .error:
                        Image(systemName: "xmark.octagon.fill")
                            .foregroundColor(.red)

                    case .blocked:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.gray)
                    }
                }
                // Gray out blocked rows visually
                .opacity(item.status == .blocked ? 0.5 : 1.0)
            }
            .frame(minHeight: 80)
        }
    }




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

private struct SectionHeader: View {
    var title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        HStack {
            Text(title)
                .font(.title3).bold()
            Spacer()
        }
        .padding(.top, 2)
        .overlay(
            Divider().offset(y: 16),
            alignment: .bottom
        )
        .padding(.bottom, 8)
    }
}

// MARK: - Small UI helpers

private struct LabeledField<Content: View>: View {
    var label: String
    var content: Content
    init(_ label: String, content: @autoclosure @escaping () -> Content) {
        self.label = label
        self.content = content()
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).frame(width: 90, alignment: .trailing)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Helper: label + menu picker, no fixed widths so it sizes naturally
private struct CompactPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) {
                    Text($0.isEmpty ? "—" : $0).tag($0)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

// Helper: position picker for burn-in options
// Compact 3×3 position selector (corners + edge centers)
private struct PositionPicker: View {
    @Binding var selection: BurnInPosition

    // 3×3 layout; center is nil/disabled
    private let rows: [[BurnInPosition?]] = [
        [.upperLeft,  .upperCenter,  .upperRight],
        [.middleLeft, nil,           .middleRight],
        [.lowerLeft,  .lowerCenter,  .lowerRight]
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 4) {
                    let row = rows[r]
                    ForEach(row.indices, id: \.self) { c in
                        PositionCell(position: row[c], selection: $selection)
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
                        .frame(width: 14, height: 14)      // ~checkbox size
                        .contentShape(Rectangle())         // generous hit area
                }
                .buttonStyle(.plain)
                .help(label(for: pos))
            } else {
                // Disabled center
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

    private func label(for p: BurnInPosition) -> String {
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
