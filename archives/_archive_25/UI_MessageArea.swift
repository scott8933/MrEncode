//
//  UI_MessageArea.swift
//  MrHEVC
//

import SwiftUI

struct UI_MessageArea: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let recent = Array(state.uiMessages.suffix(3)).reversed() // newest first
        if recent.isEmpty {
            EmptyView()
        } else {
            let latestID = recent.first?.id
            VStack(alignment: .leading, spacing: 6) {
                ForEach(recent) { m in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(color(for: m.level))
                            .frame(width: 8, height: 8)
                        Text(text(for: m))
                            .font(.callout)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .opacity(m.id == latestID ? 1.0 : 0.5) // newest full, older 50%
                }
            }
            .padding(8)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .frame(maxHeight: 84) // “a few lines as necessary but no taller”
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info:    return Color.blue.opacity(0.9)
        case .warning: return Color.orange.opacity(0.9)
        case .error:   return Color.red.opacity(0.9)
        }
    }

    private func text(for m: AppLogEntry) -> String {
        if let fn = m.filename, !fn.isEmpty {
            return "\(m.message) — \(fn)"
        } else {
            return m.message
        }
    }
}
