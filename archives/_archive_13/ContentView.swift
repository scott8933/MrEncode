import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var state: AppState

    private enum C {
        static let pad: CGFloat = 16
        static let minW: CGFloat = 640
        static let minH: CGFloat = 720
        static let actionBarHeight: CGFloat = 52
    }

    var body: some View {
        Group {
            if state.settings.autoEncodeOnDrop {
                // Compact layout: Header → Queue, pinned to top
                VStack(spacing: 16) {
                    header
                    UI_Queue()
                    Spacer(minLength: 0)                    // ← keep content at top
                }
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .topLeading)              // ← align whole stack to top
                .padding(C.pad)
            } else {
                // Full layout: Header → Queue → Main → Advanced → Deadline
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        UI_Queue()
                        UI_MainOptions()
                        UI_AdvancedOptions()
                        UI_DeadlineOptions()
                    }
                    .padding(C.pad)
                    .padding(.bottom, C.actionBarHeight + C.pad) // space for pinned bar
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !state.settings.autoEncodeOnDrop {
                UI_ActionBar(
                    canClear: !state.files.isEmpty,                                  // ← enable Clear if anything is in the list
                    canSubmit: state.files.contains { $0.status == .queued },        // ← submit only when something is queued
                    onClear: { state.clear() },
                    onSubmit: { state.submit() },
                    runMode: state.settings.runMode
                )
                .frame(height: 52)
                .background(.bar)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
            }
        }

        .frame(minWidth: C.minW, minHeight: C.minH)
        .onChange(of: state.settings.runMode) { newMode in
            state.revalidateFilesForCurrentMode()
            if newMode == .remoteDeadline && !state.deadlineAvailable {
                Task { await state.refreshDeadlineOptions(inBackground: true) }
            }
        }
    }

    // MARK: - Header (MrHEVC + Mode + Auto-Encode)
    private var header: some View {
        HStack(spacing: 12) {
            Text("MrHEVC").font(.largeTitle).bold()
            Spacer()

            Picker("Mode", selection: $state.settings.runMode) {
                ForEach(RunMode.allCases) { mode in
                    Text(mode.rawValue)
                        .fontWeight(mode == state.settings.runMode ? .semibold : .regular)
                        .foregroundColor(mode == state.settings.runMode ? .primary : .secondary)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .help("Choose Local (ffmpeg) or Remote (Deadline) execution.")

            Toggle("Auto-Encode", isOn: $state.settings.autoEncodeOnDrop)
                .help("Start encoding immediately when files are dropped.")
                .padding(.leading, 8)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Bottom Action Bar
private struct UI_ActionBar: View {
    let canClear: Bool
    let canSubmit: Bool
    let onClear: () -> Void
    let onSubmit: () -> Void
    let runMode: RunMode

    var body: some View {
        HStack {
            Button("Clear", action: onClear)
                .disabled(!canClear)   // ← only tied to canClear
            Spacer()
            Button(runMode == .remoteDeadline ? "Submit to Deadline" : "Encode Locally", action: onSubmit)
                .disabled(!canSubmit)  // ← only tied to canSubmit
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }
}

