//
//  UI_DeadlineOptions.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/16/25.
//

import SwiftUI

struct UI_DeadlineOptions: View {
    @EnvironmentObject var state: AppState

    private static let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 0
        f.maximum = 100
        return f
    }()

    var body: some View {
        let inactive = state.settings.runMode == .localFFmpeg
        let dimHeader = !state.settings.deadlineExpanded && inactive

        // Match Compression / Scale&Crop layout numbers
        let itemGap: CGFloat = 2
        let groupGap: CGFloat = 30

        VStack(alignment: .leading, spacing: 0) {

            // Header (match CompressionOptions)
            Button {
                withAnimation(.easeInOut(duration: StyleConstants.expandAnimationDuration)) {
                    state.settings.deadlineExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: state.settings.deadlineExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)

                    Text("Renderfarm Options")
                        .font(.headline)
                        .opacity(dimHeader ? 0.35 : 1.0)

                    Spacer(minLength: 8)

                    UI_DeadlineStatus()
                        .environmentObject(state)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Content
            if state.settings.deadlineExpanded {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: StyleConstants.sectionSpacing) {

                    // Priority
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {
                            HStack(spacing: itemGap) {
                                Text("Priority")
                                    .font(.headline)
                                    .frame(width: StyleConstants.deadlineLabelWidth, alignment: .leading)
                                    .fixedSize(horizontal: true, vertical: false)

                                HStack(spacing: 8) {
                                    Stepper(value: $state.settings.priority, in: 0...100) { EmptyView() }
                                        .labelsHidden()

                                    TextField("0–100",
                                              value: $state.settings.priority,
                                              formatter: Self.intFormatter)
                                        .frame(width: 64)
                                        .textFieldStyle(.roundedBorder)
                                        .multilineTextAlignment(.trailing)
                                        .help("Higher = sooner on the farm (0–100).")
                                }
                            }

                            Color.clear.frame(width: groupGap)
                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // Pool
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {
                            HStack(spacing: itemGap) {
                                Text("Pool")
                                    .font(.headline)
                                    .frame(width: StyleConstants.deadlineLabelWidth, alignment: .leading)
                                    .fixedSize(horizontal: true, vertical: false)

                                Picker("", selection: $state.settings.pool) {
                                    ForEach(state.settings.poolOptions, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: StyleConstants.deadlinePickerWidth, alignment: .leading)
                                .help("Primary farm pool.")
                            }

                            Color.clear.frame(width: groupGap)
                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // Secondary Pool
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {
                            HStack(spacing: itemGap) {
                                Text("Secondary Pool")
                                    .font(.headline)
                                    .frame(width: StyleConstants.deadlineLabelWidth, alignment: .leading)
                                    .fixedSize(horizontal: true, vertical: false)

                                Picker("", selection: $state.settings.secondaryPool) {
                                    ForEach(state.settings.poolOptions, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: StyleConstants.deadlinePickerWidth, alignment: .leading)
                                .help("Fallback pool.")
                            }

                            Color.clear.frame(width: groupGap)
                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // Group
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {
                            HStack(spacing: itemGap) {
                                Text("Group")
                                    .font(.headline)
                                    .frame(width: StyleConstants.deadlineLabelWidth, alignment: .leading)
                                    .fixedSize(horizontal: true, vertical: false)

                                Picker("", selection: $state.settings.group) {
                                    ForEach(state.settings.groupOptions, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: StyleConstants.deadlinePickerWidth, alignment: .leading)
                                .help("Machine group constraint.")
                            }

                            Color.clear.frame(width: groupGap)
                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // Divider
                    GridRow { Divider().gridCellColumns(5) }

                    // Batch Name
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {
                            HStack(spacing: itemGap) {
                                Text("Batch Name")
                                    .font(.headline)
                                    .frame(width: StyleConstants.deadlineLabelWidth, alignment: .leading)
                                    .fixedSize(horizontal: true, vertical: false)

                                TextField("optional", text: $state.settings.batchName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: StyleConstants.deadlineFieldWidth)
                            }

                            Color.clear.frame(width: groupGap)
                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // Job Name
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {
                            HStack(spacing: itemGap) {
                                Text("Job Name")
                                    .font(.headline)
                                    .frame(width: StyleConstants.deadlineLabelWidth, alignment: .leading)
                                    .fixedSize(horizontal: true, vertical: false)

                                TextField("auto from filename if blank", text: $state.settings.jobName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: StyleConstants.deadlineFieldWidth)
                            }

                            Color.clear.frame(width: groupGap)
                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // Comment
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {
                            HStack(spacing: itemGap) {
                                Text("Comment")
                                    .font(.headline)
                                    .frame(width: StyleConstants.deadlineLabelWidth, alignment: .leading)
                                    .fixedSize(horizontal: true, vertical: false)

                                TextField("optional", text: $state.settings.comment)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: StyleConstants.deadlineFieldWidth)
                            }

                            Color.clear.frame(width: groupGap)
                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // Dependencies
                    GridRow {
                        HStack(alignment: .center, spacing: 0) {
                            HStack(spacing: itemGap) {
                                Text("Dependencies")
                                    .font(.headline)
                                    .frame(width: StyleConstants.deadlineLabelWidth, alignment: .leading)
                                    .fixedSize(horizontal: true, vertical: false)

                                TextField("comma-separated Job IDs", text: $state.settings.dependencies)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: StyleConstants.deadlineFieldWidth)
                                    .help("Jobs to finish before this starts.")
                            }

                            Color.clear.frame(width: groupGap)
                            Spacer(minLength: 0)
                        }
                        .gridCellColumns(5)
                    }

                    // Divider
                    GridRow { Divider().gridCellColumns(5) }

                    // Refresh button
                    GridRow {
                        HStack {
                            Spacer()
                            Button("Refresh Pools/Groups") {
                                state.refreshDeadlineOptions(inBackground: false)
                            }
                            .help("Query farm for latest pools and groups.")
                        }
                        .gridCellColumns(5)
                    }
                }
                .padding(StyleConstants.panelInsets)
                .padding(.top, StyleConstants.panelInsets.top) // your “double header gap” rule
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: StyleConstants.expandAnimationDuration),
                   value: state.settings.deadlineExpanded)

        // --- Sticky persistence hooks (keep outside conditional so it hydrates even when collapsed) ---
        .onChange(of: state.settings.pool) { _ in PreferencesService.shared.updateSticky(from: state.settings) }
        .onChange(of: state.settings.secondaryPool) { _ in PreferencesService.shared.updateSticky(from: state.settings) }
        .onChange(of: state.settings.group) { _ in PreferencesService.shared.updateSticky(from: state.settings) }
        .onAppear {
            state.settings = PreferencesService.shared.applyStickyDeadlineFallback(to: state.settings)
        }
        // --- end sticky hooks ---
    }

}

// MARK: - Status pill in the header (top-right)

private struct UI_DeadlineStatus: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            if state.isRefreshingDeadline {
                ProgressView()
                    .scaleEffect(0.7)
                    .controlSize(.small)
                Text("Checking…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if state.deadlineAvailable {
                Circle().frame(width: 7, height: 7).foregroundColor(.green)
                Text("Ready")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if state.settings.lastDeadlineFetch != nil {
                Circle().frame(width: 7, height: 7).foregroundColor(.red)
                Text("Unavailable")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // Never fetched + not available => treat as "not detected" on this machine.
                Circle().frame(width: 7, height: 7).foregroundColor(.gray)
                Text("Not found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
    }
}
