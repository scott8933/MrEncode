//
//  VideoPreflight.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/10/25.
//


// =============================
// File: VideoPreflight.swift
// =============================
import Foundation
import AVFoundation

/// One place to analyze input dimensions vs. the app's scale and log a concise warning
/// when we auto-fix to even sizes (required by 4:2:0 pipelines).
enum VideoPreflight {

    /// Keep per-item warnings to once-per-session.
    private static var warnedIDs = Set<UUID>()
    private static let lock = NSLock()

    struct Analysis {
        let inW: Int, inH: Int
        let scaledW: Int, scaledH: Int  // naive rounded scale
        let outW: Int, outH: Int        // evenized (ceil(.../2)*2)
        let needsEvenize: Bool
    }

    /// Analyze input size and what the builder will produce after scale+evenize.
    static func analyze(url: URL, scale: ScaleOption) -> Analysis? {
        // Input dimensions via AVFoundation
        let asset = AVAsset(url: url)
        guard let t = asset.tracks(withMediaType: .video).first else { return nil }
        let s  = t.naturalSize.applying(t.preferredTransform)
        let iw = Int(abs(s.width).rounded())
        let ih = Int(abs(s.height).rounded())

        let factor: Double = {
            switch scale {
            case .oneToOne: return 1.0
            case .half:     return 0.5
            case .quarter:  return 0.25
            }
        }()

        // What the user would “expect” from a basic scale:
        let scaledW = Int((Double(iw) * factor).rounded(.toNearestOrAwayFromZero))
        let scaledH = Int((Double(ih) * factor).rounded(.toNearestOrAwayFromZero))

        // What our builder actually emits (evenize up):
        let outW = Int(ceil(Double(iw) * factor / 2.0)) * 2
        let outH = Int(ceil(Double(ih) * factor / 2.0)) * 2

        let needs = (iw % 2 != 0) || (ih % 2 != 0) || (outW != scaledW) || (outH != scaledH)

        return Analysis(inW: iw, inH: ih, scaledW: scaledW, scaledH: scaledH, outW: outW, outH: outH, needsEvenize: needs)
    }

    /// Log a single warning (per item.id) if we’re going to evenize the dimensions.
    static func warnIfEvenizeNeeded(for item: MediaItem, settings: Settings) {
        // Prevent duplicate logs for the same item in this session
        lock.lock()
        if warnedIDs.contains(item.id) { lock.unlock(); return }
        warnedIDs.insert(item.id)
        lock.unlock()

        guard let a = analyze(url: item.url, scale: settings.scale), a.needsEvenize else { return }
        AppState.shared?.log(.warning,
                             "Odd dimensions \(a.inW)x\(a.inH) auto-fixed to \(a.outW)x\(a.outH).",
                             fileURL: item.url)
    }
}
