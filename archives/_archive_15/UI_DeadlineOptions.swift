//
//  UI.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/8/25.
//


import SwiftUI

struct UI_DeadlineOptions: View {
    @EnvironmentObject var state: AppState

    private enum C {
        static let labelWidth: CGFloat = 90
        static let panelInsets = EdgeInsets(top: 6, leading: 6, bottom: 2, trailing: 6)
    }

    private static let intFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .none
        nf.minimum = 0
        nf.maximum = 100
        nf.allowsFloats = false
        return nf
    }()

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
    private var statusColor: Color { state.deadlineAvailable ? .green : .orange }

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $state.settings.deadlineExpanded) {
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

                let disabled =
                    (state.settings.runMode != .remoteDeadline) ||
                    (!state.deadlineAvailable && state.settings.poolOptions.isEmpty)

                VStack(alignment: .leading, spacing: 10) {
                    UI_LabeledField("Priority", width: C.labelWidth) {
                        TextField("0–100",
                                  value: $state.settings.priority,
                                  formatter: Self.intFormatter)
                        .textFieldStyle(.roundedBorder)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Pool").frame(width: C.labelWidth, alignment: .trailing)

                        HStack(spacing: 8) {
                            Picker("", selection: $state.settings.pool) {
                                ForEach(state.settings.poolOptions, id: \.self) {
                                    Text($0.isEmpty ? "—" : $0).tag($0)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize(horizontal: true, vertical: false)

                            UI_CompactPicker(title: "Secondary",
                                             selection: $state.settings.secondaryPool,
                                             options: state.settings.poolOptions)

                            UI_CompactPicker(title: "Group",
                                             selection: $state.settings.group,
                                             options: state.settings.groupOptions)
                        }
                    }

                    UI_LabeledField("Batch Name", width: C.labelWidth) {
                        TextField("optional", text: $state.settings.batchName)
                            .textFieldStyle(.roundedBorder)
                    }

                    UI_LabeledField("Job Name", width: C.labelWidth) {
                        TextField("optional", text: $state.settings.jobName)
                            .textFieldStyle(.roundedBorder)
                    }

                    UI_LabeledField("Comment", width: C.labelWidth) {
                        TextField("optional", text: $state.settings.comment)
                            .textFieldStyle(.roundedBorder)
                    }

                    UI_LabeledField("Dependencies", width: C.labelWidth) {
                        TextField("JobIDs comma-separated", text: $state.settings.dependencies)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .disabled(disabled)
                .animation(.default, value: disabled)
                .padding(C.panelInsets)
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
}
