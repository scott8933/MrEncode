//
//  MediaProbe.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/10/25.
//


// =============================
// File: MediaProbe.swift
// =============================
import Foundation
import AVFoundation

struct MediaBasics {
    let outW: Int
    let outH: Int
    let fps: Double
    let duration: Double
    let hasAudio: Bool
    let isHDR: Bool
}

enum MediaProbe {
    /// Read basic media facts for estimation and command decisions.
    /// Uses Metadata where available, falls back to AVAsset quickly.
    static func readBasics(url: URL,
                           meta: MediaMetadata,
                           scale: ScaleOption) -> MediaBasics? {
        let asset = AVAsset(url: url)

        // Video track + source size
        guard let v = asset.tracks(withMediaType: .video).first else { return nil }
        let sz = v.naturalSize.applying(v.preferredTransform)
        let srcW = Int(abs(sz.width).rounded())
        let srcH = Int(abs(sz.height).rounded())
        guard srcW > 0, srcH > 0 else { return nil }

        // Scaled (pre-evenize; estimation does not need exact even)
        let s = scale.factor
        let outW = max(1, Int(round(Double(srcW) * s)))
        let outH = max(1, Int(round(Double(srcH) * s)))

        // Timing
        let fps = meta.nominalFPS ?? (v.nominalFrameRate > 0 ? Double(v.nominalFrameRate) : 30.0)
        let dur = meta.durationSeconds ?? CMTimeGetSeconds(asset.duration)
        guard dur.isFinite, dur > 0 else { return nil }

        // Audio
        let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty

        // HDR?
        let tf = (meta.transferFunction ?? "").lowercased()
        let isHDR = tf.contains("2084") || tf.contains("pq") || tf.contains("hlg") || tf.contains("2100")

        return MediaBasics(outW: outW, outH: outH, fps: fps, duration: dur, hasAudio: hasAudio, isHDR: isHDR)
    }
}
