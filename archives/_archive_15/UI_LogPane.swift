import SwiftUI

struct UI_LogPane: View {
    @EnvironmentObject var state: AppState

    // Filtering
    private enum Filter: Hashable, CaseIterable {
        case all, warnings, errors
        var title: String {
            switch self {
            case .all:      return "All"
            case .warnings: return "Warnings"
            case .errors:   return "Errors"
            }
        }
    }
    @State private var filter: Filter = .all

    // Timestamp format
    private static let tsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        VStack(spacing: 8) {
            headerBar()

            contentList(entries: filteredLogs())
                .frame(maxHeight: state.showLogPane ? 160 : 44)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            expanderBar()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func headerBar() -> some View {
        HStack(spacing: 8) {
            Text("Messages").font(.headline)
            Spacer()

            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            Button {
                state.clearLogs()
            } label: {
                Image(systemName: "trash")
                Text("Clear")
            }
            .disabled(state.logs.isEmpty) // rename if your property isn't `logs`
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func contentList(entries: [AppLogEntry]) -> some View {
        if entries.isEmpty {
            Text("No messages yet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 8)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { e in
                            LogRowView(
                                ts: UI_LogPane.tsFormatter.string(from: e.date),
                                level: e.level,
                                message: e.message,
                                fileName: e.filename
                            )
                            .id(e.id)
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(.vertical, 6)
                }
                // Use count to avoid Equatable conformance on entry type
                .onChange(of: state.logs.count) { _ in
                    if let last = entries.last {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func expanderBar() -> some View {
        HStack(spacing: 8) {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                    state.showLogPane.toggle()
                }
            } label: {
                Image(systemName: state.showLogPane ? "chevron.down" : "chevron.up")
                Text(state.showLogPane ? "Hide details" : "Show details")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Filtering

    private func filteredLogs() -> [AppLogEntry] {
        switch filter {
        case .all:
            return state.logs
        case .warnings:
            return state.logs.filter { $0.level == .warning }
        case .errors:
            return state.logs.filter { $0.level == .error }
        }
    }

    // MARK: - Row

    private struct LogRowView: View {
        let ts: String
        let level: LogLevel
        let message: String
        let fileName: String?

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ts)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)

                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .padding(.trailing, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(message).font(.callout)
                    if let fileName {
                        Text(fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
        }

        private var dotColor: Color {
            switch level {
            case .error:   return .red
            case .warning: return .yellow
            case .info:    return .secondary
            }
        }
    }
}
