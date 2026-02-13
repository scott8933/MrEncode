// =============================
// File: DropZoneView.swift
// =============================

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct DropZoneView: View {
    @EnvironmentObject var state: AppState
    @State private var isTargeted = false
    var onURLs: ([URL]) -> Void

    private enum C {
        static let corner: CGFloat = 12
        static let dash: [CGFloat] = [6, 6]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: C.corner)
            .strokeBorder(isTargeted ? Color.accentColor : Color.secondary,
                          style: StrokeStyle(lineWidth: 2, dash: C.dash))
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 26, weight: .regular))
                        .opacity(0.6)
                    Text("Drop QuickTime files here")
                        .foregroundColor(.secondary)
                }
                .padding(12)
            )
            .onDrop(of: [UTType.fileURL, UTType.movie, UTType.quickTimeMovie],
                    isTargeted: $isTargeted, perform: handleDrop(providers:))
    }

    // MARK: - Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        let group = DispatchGroup()
        var results: [URL] = []
        var rejected: [String] = []

        func push(_ u: URL?) {
            guard let u = u?.standardizedFileURL, u.isFileURL else { return }
            if isAllowedQuickTime(u) {
                results.append(u)
            } else {
                rejected.append(u.lastPathComponent)
            }
        }

        // fileURL flavor
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let url = item as? URL {
                    push(url)
                } else if let ns = item as? NSURL {
                    push(ns as URL)
                }
            }
        }

        // movie flavors
        let movieUTIs = [UTType.movie.identifier, UTType.quickTimeMovie.identifier]
        for p in providers where movieUTIs.contains(where: { p.hasItemConformingToTypeIdentifier($0) }) {
            accepted = true
            for uti in movieUTIs where p.hasItemConformingToTypeIdentifier(uti) {
                group.enter()
                p.loadItem(forTypeIdentifier: uti, options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL {
                        push(url)
                    } else if let ns = item as? NSURL {
                        push(ns as URL)
                    } else if let s = item as? String {
                        if let u = URL(string: s), u.isFileURL { push(u) }
                        else { push(URL(fileURLWithPath: s)) }
                    }
                }
            }
        }

        group.notify(queue: .main) {
            // Dedup & hand off
            let unique = Array(Set(results))
            if !unique.isEmpty {
                // Sanity messages for each accepted file
                for u in unique {
                    sanityCheckEvenize(for: u, settings: state.settings)
                }
                onURLs(unique)
            }
            if !rejected.isEmpty {
                AppState.shared?.pushMessage(level: .warning,
                                             "Unsupported file(s) skipped",
                                             filename: rejected.prefix(3).joined(separator: ", "))
            }
        }

        return accepted
    }

    // MARK: - Sanity checks

    /// Warn when the (scaled) output dims will be odd and need evenizing.
    /// Also warn when the *source* is odd and scale is 1:1 (we'll evenize on encode).
    private func sanityCheckEvenize(for url: URL, settings: Settings) {
        let asset = AVAsset(url: url)
        guard let v = asset.tracks(withMediaType: .video).first else { return }
        let natural = v.naturalSize
        let tx = v.preferredTransform
        // account for rotation
        let r = natural.applying(tx)
        let srcW = Int(abs(r.width).rounded())
        let srcH = Int(abs(r.height).rounded())
        guard srcW > 0, srcH > 0 else { return }

        let factor = settings.scale.factor
        let rawW = max(1, Int(round(Double(srcW) * factor)))
        let rawH = max(1, Int(round(Double(srcH) * factor)))
        let evenW = (rawW / 2) * 2
        let evenH = (rawH / 2) * 2

        if rawW != evenW || rawH != evenH {
            AppState.shared?.pushMessage(
                level: .warning,
                "Non-even dims will be evenized: \(rawW)×\(rawH) → \(evenW)×\(evenH)",
                filename: url.lastPathComponent
            )
        } else if (srcW % 2 != 0 || srcH % 2 != 0) && factor == 1.0 {
            AppState.shared?.pushMessage(
                level: .warning,
                "Source has odd dims; output will be \(evenW)×\(evenH)",
                filename: url.lastPathComponent
            )
        }
    }

    // MARK: - Helpers

    private func isAllowedQuickTime(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "mov" || ext == "qt"
    }
}
