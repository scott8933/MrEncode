import Foundation
import AVFoundation

struct EncodeTimeEstimator {

    /// Predict wall time in seconds for *local* encodes.
    /// Returns nil in Remote mode or if media info can’t be read.
    static func estimateSeconds(url: URL,
                                meta: MediaMetadata,
                                settings: Settings,
                                runMode: RunMode) -> Double? {

        // Do not estimate in Remote mode
        guard runMode == .localFFmpeg else { return nil }

        let asset = AVAsset(url: url)

        // Prefer metadata where available (comes from your ExifTool/metadata pass)
        let fpsMeta = meta.nominalFPS
        let durMeta = meta.durationSeconds

        // Dimensions: use AVAsset track (fast enough for local files)
        guard let vTrack = asset.tracks(withMediaType: .video).first else { return nil }
        let srcSize = vTrack.naturalSize.applying(vTrack.preferredTransform)
        let srcW = Int(abs(srcSize.width).rounded())
        let srcH = Int(abs(srcSize.height).rounded())
        guard srcW > 0, srcH > 0 else { return nil }

        let scale = settings.scale.factor
        let outW = max(1, Int(round(Double(srcW) * scale)))
        let outH = max(1, Int(round(Double(srcH) * scale)))

        // Timing: prefer meta; fall back to track/asset
        let fps = fpsMeta ?? (vTrack.nominalFrameRate > 0 ? Double(vTrack.nominalFrameRate) : 30.0)
        let secsRaw = durMeta ?? CMTimeGetSeconds(asset.duration)
        guard secsRaw.isFinite, secsRaw > 0 else { return nil }
        let duration = secsRaw

        // Throughput (MP/s) from stats (bucketed) or fallback default
        let mpps = EncodeStatsStore.shared.averageMPps(runMode: "local",
                                                       outW: outW, outH: outH,
                                                       fps: fps, crf: settings.qualityCRF)
                 ?? defaultThroughputMPps(for: .localFFmpeg, outW: outW, outH: outH)

        let mpTotal = Double(outW * outH) * fps * duration / 1_000_000.0
        guard mpTotal > 0, mpps > 0 else { return nil }

        return mpTotal / mpps
    }


    /// After a *local* encode finishes, call this to teach the estimator.
    static func recordCompleted(url: URL,
                                meta: MediaMetadata,
                                settings: Settings,
                                runMode: RunMode,
                                startedAt: Date,
                                finishedAt: Date) {
        // Only learn from Local runs
        guard runMode == .localFFmpeg else { return }

        let wall = max(0, finishedAt.timeIntervalSince(startedAt))

        let asset = AVAsset(url: url)
        guard let vTrack = asset.tracks(withMediaType: .video).first else { return }

        let srcSize = vTrack.naturalSize.applying(vTrack.preferredTransform)
        let srcW = Int(abs(srcSize.width).rounded())
        let srcH = Int(abs(srcSize.height).rounded())

        let scale = settings.scale.factor
        let outW = max(1, Int(round(Double(srcW) * scale)))
        let outH = max(1, Int(round(Double(srcH) * scale)))

        let fps = meta.nominalFPS ?? (vTrack.nominalFrameRate > 0 ? Double(vTrack.nominalFrameRate) : 30.0)
        let duration = max(0, meta.durationSeconds ?? CMTimeGetSeconds(asset.duration))

        let sample = EncodeStatsStore.makeSample(
            runMode: "local",
            outW: outW, outH: outH,
            fps: fps,
            durationSec: duration,
            wallTimeSec: wall,
            crf: settings.qualityCRF
        )
        EncodeStatsStore.shared.record(sample: sample)
    }

    // MARK: - Fallback heuristics

    /// Conservative defaults until we learn (mega-pixels/sec).
    private static func defaultThroughputMPps(for runMode: RunMode, outW: Int, outH: Int) -> Double {
        let long = max(outW, outH)
        switch runMode {
        case .localFFmpeg:
            return (long >= 3840) ? 12 : 18   // 4K: 12 MP/s, ≤1080p: 18 MP/s
        case .remoteDeadline:
            // Not used (we don't estimate remote), but leave a reasonable number.
            return (long >= 3840) ? 25 : 30
        }
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
