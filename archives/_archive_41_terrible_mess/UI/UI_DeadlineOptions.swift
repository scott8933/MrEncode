//
//  UI_DeadlineOptions.swift
//  MrHEVC
//

import SwiftUI

struct UI_DeadlineOptions: View {
    @EnvironmentObject var state: AppState

    private enum C {
        static let labelWidth: CGFloat = 110
        static let pickerWidth: CGFloat = 240
        static let fieldWidth: CGFloat = 320
        static let panelInsets = EdgeInsets(top: 6, leading: 12, bottom: 2, trailing: 6)
        static let rowSpacing: CGFloat = 12
    }

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
                VStack(alignment: .leading, spacing: C.rowSpacing) {

                    // Priority (stepper + manual entry)
                    UI_LabeledField("Priority", width: C.labelWidth) {
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

                    // Pool
                    UI_LabeledField("Pool", width: C.labelWidth) {
                        Picker("", selection: $state.settings.pool) {
                            ForEach(state.settings.poolOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: C.pickerWidth, alignment: .leading)
                        .help("Primary farm pool.")
                    }

                    // Secondary Pool (optional)
                    UI_LabeledField("Secondary Pool", width: C.labelWidth) {
                        Picker("", selection: $state.settings.secondaryPool) {
                            ForEach(state.settings.poolOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: C.pickerWidth, alignment: .leading)
                        .help("Fallback pool.")
                    }

                    // Group
                    UI_LabeledField("Group", width: C.labelWidth) {
                        Picker("", selection: $state.settings.group) {
                            ForEach(state.settings.groupOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: C.pickerWidth, alignment: .leading)
                        .help("Machine group constraint.")
                    }

                    Divider().padding(.vertical, 2)

                    // Batch / Job / Comment
                    UI_LabeledField("Batch Name", width: C.labelWidth) {
                        TextField("optional", text: $state.settings.batchName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: C.fieldWidth)
                    }

                    UI_LabeledField("Job Name", width: C.labelWidth) {
                        TextField("auto from filename if blank", text: $state.settings.jobName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: C.fieldWidth)
                    }

                    UI_LabeledField("Comment", width: C.labelWidth) {
                        TextField("optional", text: $state.settings.comment)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: C.fieldWidth)
                    }

                    UI_LabeledField("Dependencies", width: C.labelWidth) {
                        TextField("comma-separated Job IDs", text: $state.settings.dependencies)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: C.fieldWidth)
                            .help("Jobs to finish before this starts.")
                    }

                    Divider().padding(.vertical, 2)

                    // Refresh button only (deadlinecommand removed)
                    HStack {
                        Spacer()
                        Button("Refresh Pools/Groups") {
                            state.refreshDeadlineOptions(inBackground: false)
                        }
                        .help("Query farm for latest pools and groups.")
                    }
                }
                .padding(C.panelInsets)
            } label: {
                let inactive = state.settings.runMode == .localFFmpeg
                HStack(spacing: 8) {
                    Text("Deadline Options")
                        .font(.headline)
                        .opacity(inactive ? 0.35 : 1)
                    Spacer(minLength: 8)
                    UI_DeadlineStatus()
                        .environmentObject(state)
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
