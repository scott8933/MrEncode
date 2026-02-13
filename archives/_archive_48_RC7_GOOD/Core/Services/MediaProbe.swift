//
//  MediaProbe.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/10/25.
//

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
    /// Local in-memory cache so we don’t re-probe the same file repeatedly.
    private static var cache = [URL: MediaBasics]()
    private static let queue = DispatchQueue(label: "media.probe.queue", qos: .userInitiated)

    /// Read basic media facts synchronously. Prefer `probeAsync` in UI contexts.
    static func readBasics(url: URL,
                           meta: MediaMetadata,
                           scale: ScaleOption) -> MediaBasics? {
        // Cached? return immediately
        if let cached = cache[url] { return cached }

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
        let assetDuration = CMTimeGetSeconds(asset.duration)
        let durSource = meta.durationSeconds
        let dur = (durSource > 0 ? durSource : assetDuration)
        guard dur.isFinite, dur > 0 else { return nil }

        // Audio
        let hasAudio = !asset.tracks(withMediaType: .audio).isEmpty

        // HDR?
        let tf = (meta.transferFunction ?? "").lowercased()
        let isHDR = tf.contains("2084") || tf.contains("pq") || tf.contains("hlg") || tf.contains("2100")

        let basics = MediaBasics(outW: outW, outH: outH, fps: fps, duration: dur, hasAudio: hasAudio, isHDR: isHDR)
        cache[url] = basics
        return basics
    }

    /// Async probe with placeholder + completion. Keeps UI responsive.
    static func probeAsync(url: URL,
                           meta: MediaMetadata,
                           scale: ScaleOption,
                           completion: @escaping (MediaBasics?) -> Void) {
        // If cached, return immediately
        if let cached = cache[url] {
            completion(cached)
            return
        }

        // Return nil immediately (placeholder) so UI can render quickly
        completion(nil)

        queue.async {
            let basics = readBasics(url: url, meta: meta, scale: scale)
            DispatchQueue.main.async {
                if let basics = basics { cache[url] = basics }
                completion(basics)
            }
        }
    }
}
