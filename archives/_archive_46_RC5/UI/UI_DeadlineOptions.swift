//
//  UI_DeadlineOptions.swift
//  MrHEVC
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
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.deadlineExpanded) {
                VStack(alignment: .leading, spacing: StyleConstants.rowSpacingDefault) {

                    UI_LabeledField("Priority", width: StyleConstants.deadlineLabelWidth) {
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

                    UI_LabeledField("Pool", width: StyleConstants.deadlineLabelWidth) {
                        Picker("", selection: $state.settings.pool) {
                            ForEach(state.settings.poolOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: StyleConstants.deadlinePickerWidth, alignment: .leading)
                        .help("Primary farm pool.")
                    }

                    UI_LabeledField("Secondary Pool", width: StyleConstants.deadlineLabelWidth) {
                        Picker("", selection: $state.settings.secondaryPool) {
                            ForEach(state.settings.poolOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: StyleConstants.deadlinePickerWidth, alignment: .leading)
                        .help("Fallback pool.")
                    }

                    UI_LabeledField("Group", width: StyleConstants.deadlineLabelWidth) {
                        Picker("", selection: $state.settings.group) {
                            ForEach(state.settings.groupOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: StyleConstants.deadlinePickerWidth, alignment: .leading)
                        .help("Machine group constraint.")
                    }

                    Divider().padding(.vertical, 2)

                    UI_LabeledField("Batch Name", width: StyleConstants.deadlineLabelWidth) {
                        TextField("optional", text: $state.settings.batchName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: StyleConstants.deadlineFieldWidth)
                    }

                    UI_LabeledField("Job Name", width: StyleConstants.deadlineLabelWidth) {
                        TextField("auto from filename if blank", text: $state.settings.jobName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: StyleConstants.deadlineFieldWidth)
                    }

                    UI_LabeledField("Comment", width: StyleConstants.deadlineLabelWidth) {
                        TextField("optional", text: $state.settings.comment)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: StyleConstants.deadlineFieldWidth)
                    }

                    UI_LabeledField("Dependencies", width: StyleConstants.deadlineLabelWidth) {
                        TextField("comma-separated Job IDs", text: $state.settings.dependencies)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: StyleConstants.deadlineFieldWidth)
                            .help("Jobs to finish before this starts.")
                    }

                    Divider().padding(.vertical, 2)

                    HStack {
                        Spacer()
                        Button("Refresh Pools/Groups") {
                            state.refreshDeadlineOptions(inBackground: false)
                        }
                        .help("Query farm for latest pools and groups.")
                    }
                }
                .padding(StyleConstants.panelInsets)
            } label: {
                let inactive = state.settings.runMode == .localFFmpeg
                HStack(spacing: 8) {
                    Text("Deadline Options")
                        .font(.headline)
                        .opacity(inactive ? 0.35 : 1)
                    Spacer(minLength: 8)
                    UI_DeadlineStatus().environmentObject(state)
                }
            }
        }
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
                Circle().frame(width: 7, height: 7).foregroundColor(.gray)
                Text("Unknown")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
    }
}
