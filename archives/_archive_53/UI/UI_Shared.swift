//
//  UI_Shared.swift
//  MrEncode
//
//  Created by Scott Ulrich on 9/8/25.
//

// =============================
// File: UI_Shared.swift
// =============================

import SwiftUI
import AppKit
import Foundation


// Visual Section Header (stateless atom)
struct UI_SectionHeader: View {
    var title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        HStack { Text(title).font(.title3).bold(); Spacer() }
            .padding(.top, 2)
            .overlay(Divider().offset(y: 16), alignment: .bottom)
            .padding(.bottom, 8)
    }
}

public var sharedMaterialBackground: some View {
    Group {
        if #available(macOS 12.0, *) {
            Rectangle().fill(StyleConstants.panelFill).opacity(0.55) // CHANGED: Use AppColors
        } else {
            StyleConstants.panelFill.opacity(0.80) // CHANGED: Use AppColors (was Color(nsColor: .windowBackgroundColor))
        }
    }
}

// MARK: - Apply separator pref to suffix Auto-Fill

func suggestedSeparator(from settings: Settings) -> String {
    let sep = sanitizeSuffixSeparator(settings.suffixSeparator)
    return sep.isEmpty ? "-" : sep
}

func applySuggestedSeparator(
    _ token: String,
    settings: Settings
) -> String {
    let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return "" }

    let sep = suggestedSeparator(from: settings)

    // Strip exactly one leading instance of the current separator (supports multi-char)
    let stripped: String
    if t.hasPrefix(sep) {
        stripped = String(t.dropFirst(sep.count))
    } else {
        stripped = t
    }

    return sep + stripped
}


import Foundation

func sanitizeSuffixSeparator(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    // Allow explicit empty separator
    if trimmed.isEmpty { return "" }

    // Disallow path separators + control characters (+ ":" recommended)
    var forbidden = CharacterSet.controlCharacters
    forbidden.insert(charactersIn: "/\\:;")

    // Remove forbidden scalars
    let scalars = trimmed.unicodeScalars.filter { !forbidden.contains($0) }
    var out = String(String.UnicodeScalarView(scalars))

    // Keep it short and intentional (tweak as you like)
    if out.count > 8 {
        out = String(out.prefix(8))
    }

    return out
}



// MARK: - Label + Field Row
struct UI_LabeledField<Content: View>: View {
    let label: String
    let width: CGFloat
    let fills: Bool
    let content: () -> Content

    init(_ label: String,
         width: CGFloat = 90,
         fills: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.width = width
        self.fills = fills
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).frame(width: width, alignment: .trailing)
            if fills { content().frame(maxWidth: .infinity, alignment: .leading) }
            else { content() }
        }
    }
}

// MARK: - Compact menu picker with inline label
struct UI_CompactPicker: View {
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
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Reveal link (used when item is rendered)
struct UI_RevealLink: View {
    let title: String
    let url: URL
    var enabled: Bool = true
    var inactiveColor: Color = .secondary
    @State private var hovering = false

    var body: some View {
        Button {
            if enabled { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        } label: {
            Text(title)
                .font(.callout)
                .foregroundColor(enabled ? (hovering ? .blue : .secondary) : inactiveColor)
                .underline(enabled && hovering, color: .blue.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 2)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            guard enabled else { hovering = false; return }
            hovering = inside
            inside ? NSCursor.pointingHand.push() : NSCursor.pop()
        }
        .help(enabled ? "Reveal in Finder" : "Not available until rendered")
    }
}


// MARK: - 3x3 Position Picker
struct UI_PositionPicker: View {
    @Binding var selection: BurnInPosition

    private let grid: [[BurnInPosition]] = [
        [.upperLeft,  .upperCenter,  .upperRight],
        [.middleLeft, .center,       .middleRight],
        [.lowerLeft,  .lowerCenter,  .lowerRight]
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(grid.indices, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(grid[r].indices, id: \.self) { c in
                        UI_PositionCell(position: grid[r][c], selection: $selection)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Position")
    }
}

private struct UI_PositionCell: View {
    let position: BurnInPosition
    @Binding var selection: BurnInPosition

    var body: some View {
        let isSelected = (selection == position)

        Button { selection = position } label: {
            RoundedRectangle(cornerRadius: 3)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.45),
                        lineWidth: isSelected ? 2 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .frame(width: 12, height: 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip(for: position))
    }

    private func tooltip(for p: BurnInPosition) -> String {
        switch p {
        case .upperLeft:   return "Upper Left"
        case .upperCenter: return "Top Center"
        case .upperRight:  return "Upper Right"
        case .middleLeft:  return "Middle Left"
        case .center:      return "Center"
        case .middleRight: return "Middle Right"
        case .lowerLeft:   return "Lower Left"
        case .lowerCenter: return "Bottom Center"
        case .lowerRight:  return "Lower Right"
        }
    }
}


// MARK: - Color helpers (hex ↔ Color)
func UI_ColorFromHex(_ hex: String, alpha: Double) -> Color {
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

func UI_RGBA(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double)? {
    guard let cg = color.cgColor,
          let ns = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) else { return nil }
    return (Double(ns.redComponent),
            Double(ns.greenComponent),
            Double(ns.blueComponent),
            Double(ns.alphaComponent))
}

func UI_HexRGB(_ r: Double, _ g: Double, _ b: Double) -> String {
    let R = max(0, min(255, Int(round(r * 255))))
    let G = max(0, min(255, Int(round(g * 255))))
    let B = max(0, min(255, Int(round(b * 255))))
    return String(format: "#%02X%02X%02X", R, G, B)
}

// MARK: - QuickTime gate
func UI_IsAllowedQuickTime(_ url: URL) -> Bool {
    if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
        return type == .quickTimeMovie || type.conforms(to: .quickTimeMovie)
    }
    return url.pathExtension.lowercased() == "mov"
}
