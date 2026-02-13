//
//  EncodeTimeEstimator.swift
//  MrHEVC
//
//  Created by Scott Ulrich on 9/8/25.
//


import Foundation
import AVFoundation

struct EncodeTimeEstimator {

    /// Predict wall time in seconds. Returns nil if media info can’t be read.
    static func estimateSeconds(url: URL,
                                meta: MediaMetadata,
                                settings: Settings,
                                runMode: RunMode) -> Double? {

        let asset = AVAsset(url: url)
        guard let vTrack = asset.tracks(withMediaType: .video).first else { return nil }

        // Output geometry
        let srcSize = vTrack.naturalSize.applying(vTrack.preferredTransform)
        let srcW = Int(abs(srcSize.width).rounded())
        let srcH = Int(abs(srcSize.height).rounded())
        guard srcW > 0, srcH > 0 else { return nil }
        let scale = settings.scale.factor
        let outW = max(1, Int(round(Double(srcW) * scale)))
        let outH = max(1, Int(round(Double(srcH) * scale)))

        // Timing
        let fps = meta.nominalFPS ?? (vTrack.nominalFrameRate > 0 ? Double(vTrack.nominalFrameRate) : 30.0)
        let secsRaw = meta.durationSeconds ?? CMTimeGetSeconds(asset.duration)
        guard secsRaw.isFinite, secsRaw > 0 else { return nil }
        let duration = secsRaw

        // Throughput (MP/s) from stats or fallback default
        let crf = settings.qualityCRF
        let runModeStr = (runMode == .remote) ? "remote" : "local"
        let mpps = EncodeStatsStore.shared.averageMPps(runMode: runModeStr,
                                                       outW: outW, outH: outH,
                                                       fps: fps, crf: crf)
                 ?? defaultThroughputMPps(for: runMode, outW: outW, outH: outH)

        // Total megapixels to encode
        let mpTotal = Double(outW * outH) * fps * duration / 1_000_000.0
        guard mpTotal > 0, mpps > 0 else { return nil }

        return mpTotal / mpps
    }

    /// After an encode finishes, call this to teach the estimator.
    static func recordCompleted(url: URL,
                                meta: MediaMetadata,
                                settings: Settings,
                                runMode: RunMode,
                                startedAt: Date,
                                finishedAt: Date) {
        let wall = max(0, finishedAt.timeIntervalSince(startedAt))

        // Pull the same geometry/timing we used to estimate
        let asset = AVAsset(url: url)
        guard let vTrack = asset.tracks(withMediaType: .video).first else { return }
        let srcSize = vTrack.naturalSize.applying(vTrack.preferredTransform)
        let srcW = Int(abs(srcSize.width).rounded())
        let srcH = Int(abs(srcSize.height).rounded())
        let scale = settings.scale.factor
        let outW = max(1, Int(round(Double(srcW) * scale)))
        let outH = max(1, Int(round(Double(srcH) * scale)))

        let fps = meta.nominalFPS ?? (vTrack.nominalFrameRate > 0 ? Double(vTrack.nominalFrameRate) : 30.0)
        let duration = (meta.durationSeconds ?? CMTimeGetSeconds(asset.duration))

        let sample = EncodeStatsStore.makeSample(
            runMode: (runMode == .remote) ? "remote" : "local",
            outW: outW, outH: outH,
            fps: fps,
            durationSec: max(0, duration),
            wallTimeSec: wall,
            crf: settings.qualityCRF
        )
        EncodeStatsStore.shared.record(sample: sample)
    }

    // MARK: - Fallback heuristics

    /// Conservative defaults until we learn (mega-pixels/sec).
    private static func defaultThroughputMPps(for runMode: RunMode, outW: Int, outH: Int) -> Double {
        // Pick a slightly lower default for 10-bit HEVC libx265 "fast"
        // (these will quickly be replaced by learned stats).
        let long = max(outW, outH)
        let base: Double
        if runMode == .remote {
            // Assume farm nodes are faster on average
            base = long >= 3840 ? 25 : 30   // 4K: 25 MP/s, 1080p: 30 MP/s
        } else {
            base = long >= 3840 ? 12 : 18   // 4K: 12 MP/s, 1080p: 18 MP/s
        }
        return base
    }

    // MARK: - UI helper
    static func formatTime(_ seconds: Double) -> String {
        if seconds < 1 { return String(format: "%.1fs", seconds) }
        if seconds < 90 { return String(format: "%.0fs", seconds) }
        let m = Int(seconds / 60.0)
        let s = Int(seconds.truncatingRemainder(dividingBy: 60.0))
        if m < 60 { return String(format: "%dm %02ds", m, s) }
        let h = m / 60
        let mm = m % 60
        return String(format: "%dh %02dm", h, mm)
    }
}
