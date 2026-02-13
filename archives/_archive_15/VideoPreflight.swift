// =============================
// File: VideoPreflight.swift
// =============================
import Foundation
import AVFoundation

/// One place to analyze input dimensions vs. app scale and log a concise warning
/// when we auto-fix to even sizes (required by yuv420).
enum VideoPreflight {

    // De-dupe “same item” warnings within a session
    private static var warnedIDs = Set<UUID>()
    private static let lock = NSLock()

    struct Analysis {
        let inW: Int, inH: Int
        let scaledW: Int, scaledH: Int  // naive rounded scale
        let outW: Int, outH: Int        // evenized ceil(.../2)*2
        let needsEvenize: Bool
    }

    static func analyze(url: URL, scale: ScaleOption) -> Analysis? {
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

        // What a simple scale would suggest:
        let scaledW = Int((Double(iw) * factor).rounded(.toNearestOrAwayFromZero))
        let scaledH = Int((Double(ih) * factor).rounded(.toNearestOrAwayFromZero))

        // What our builder actually emits (evenize up):
        let outW = Int(ceil(Double(iw) * factor / 2.0)) * 2
        let outH = Int(ceil(Double(ih) * factor / 2.0)) * 2

        let needs = (iw % 2 != 0) || (ih % 2 != 0) || (outW != scaledW) || (outH != scaledH)
        return Analysis(inW: iw, inH: ih, scaledW: scaledW, scaledH: scaledH, outW: outW, outH: outH, needsEvenize: needs)
    }

    /// Log only once per item id.
    static func warnIfEvenizeNeeded(for item: MediaItem, settings: Settings) {
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
